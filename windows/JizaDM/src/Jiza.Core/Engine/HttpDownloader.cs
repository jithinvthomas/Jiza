using System.Buffers;
using System.Net;
using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using Jiza.Core.Model;
using Microsoft.Win32.SafeHandles;

namespace Jiza.Core.Engine;

/// Multi-connection HTTP(S) downloader. Splits the file into ranges, fetches them in parallel and,
/// when a connection runs out of work, splits the largest remaining range in half (dynamic segmentation),
/// so every connection stays busy until the last byte. Falls back to a single stream when the server ignores Range.
public sealed class HttpDownloader : IDownloader
{
    public const long MinSegment = 512 * 1024;
    const int BufferSize = 256 * 1024;
    const int MaxRetries = 8;
    public static TimeSpan StallTimeout { get; set; } = TimeSpan.FromSeconds(20);

    public DownloadKind Kind => DownloadKind.Http;

    sealed class RangeLostException : Exception;
    /// The server refused this extra connection (429/503); the remaining connections take over its range.
    sealed class ServerBusyException : Exception;
    /// Per-download state shared by its connections.
    sealed class Run { public int LiveWorkers; }

    public async Task RunAsync(DownloadItem item, DownloadContext context, CancellationToken ct)
    {
        try { await RunCoreAsync(item, context, ct); }
        catch (RangeLostException)
        {
            // The file changed on the server (If-Range failed) or ranges stopped working: start over.
            Reset(item);
            await RunCoreAsync(item, context, ct);
        }
    }

    public static void Reset(DownloadItem item)
    {
        if (item.PartPath is { } part) TryDelete(part);
        lock (item.SegmentLock) item.Segments.Clear();
        item.DownloadedBytes = 0;
        item.TotalBytes = -1;
        item.Resumable = false;
        item.Validator = null;
    }

    async Task RunCoreAsync(DownloadItem item, DownloadContext ctx, CancellationToken ct)
    {
        var url = new Uri(item.Url);
        var limiter = item.SpeedLimit > 0 ? new SpeedLimiter(item.SpeedLimit) : null;
        item.State = DownloadState.Connecting;
        item.Status = "Connecting";

        var resuming = item.Resumable && item.TotalBytes > 0 && item.Segments.Count > 0 && item.PartPath is { } p && File.Exists(p);
        if (!resuming)
        {
            using var probe = ctx.Request(item, url);
            probe.Headers.Range = new RangeHeaderValue(0, null);
            using var response = await ctx.Http.SendAsync(probe, HttpCompletionOption.ResponseHeadersRead, ct);
            if (!response.IsSuccessStatusCode) throw DownloadException.ForStatus((int)response.StatusCode);

            var finalUrl = response.RequestMessage?.RequestUri ?? url;
            var headers = response.Content.Headers;
            if (string.IsNullOrWhiteSpace(item.FileName))
                item.FileName = FileNaming.FromResponse(finalUrl, headers.ContentDisposition?.ToString(), headers.ContentType?.MediaType);
            item.Validator = response.Headers.ETag?.ToString() ?? headers.LastModified?.ToString("R");

            var ranged = response.StatusCode == HttpStatusCode.PartialContent && headers.ContentRange?.Length is > 0;
            item.TotalBytes = ranged ? headers.ContentRange!.Length!.Value : headers.ContentLength ?? -1;
            item.Resumable = ranged;
            Directory.CreateDirectory(item.Folder);
            // Only this item's own stale data is removed; another download of the same name keeps its part file.
            if (item.PartPath is { } stale) TryDelete(stale);
            item.PartPath = FileNaming.Reserve(item.Folder, item.FileName + ".jdpart");

            if (!ranged)
            {
                await SingleStreamAsync(item, ctx, response, limiter, ct);
                Finish(item);
                return;
            }
            PlanSegments(item);
        }

        await SegmentedAsync(item, ctx, url, limiter, ct);
        Finish(item);
    }

    static void PlanSegments(DownloadItem item)
    {
        var total = item.TotalBytes;
        var count = (int)Math.Clamp(Math.Min(item.Connections, total / MinSegment), 1, 32);
        var size = total / count;
        lock (item.SegmentLock)
        {
            item.Segments.Clear();
            for (var i = 0; i < count; i++)
                item.Segments.Add(new Segment { Start = i * size, End = i == count - 1 ? total - 1 : (i + 1) * size - 1 });
        }
    }

    async Task SegmentedAsync(DownloadItem item, DownloadContext ctx, Uri url, SpeedLimiter? limiter, CancellationToken ct)
    {
        Preallocate(item.PartPath!, item.TotalBytes);
        using var handle = File.OpenHandle(item.PartPath!, FileMode.Open, FileAccess.ReadWrite, FileShare.Read, FileOptions.Asynchronous);
        using var stop = CancellationTokenSource.CreateLinkedTokenSource(ct);
        item.State = DownloadState.Downloading;
        item.Status = "Downloading";

        var run = new Run { LiveWorkers = Math.Clamp(item.Connections, 1, 32) };
        var workers = Enumerable.Range(0, run.LiveWorkers)
            .Select(_ => WorkerAsync(item, ctx, url, handle, limiter, run, stop.Token)).ToList();
        var monitor = MonitorAsync(item, ctx, stop.Token);
        try
        {
            // The first failure stops the other connections so the error surfaces promptly.
            var pending = new List<Task>(workers);
            while (pending.Count > 0)
            {
                var done = await Task.WhenAny(pending);
                pending.Remove(done);
                if (done.IsFaulted || done.IsCanceled) { stop.Cancel(); break; }
            }
            await Task.WhenAll(workers);
        }
        finally
        {
            stop.Cancel();
            try { await monitor; } catch (OperationCanceledException) { }
            item.ActiveConnections = 0;
            UpdateProgress(item);
            ctx.Checkpoint(item);
        }

        lock (item.SegmentLock)
            if (item.Segments.Any(s => !s.Done)) throw new DownloadException("Download stopped before all parts finished.", retryable: true);
    }

    async Task WorkerAsync(DownloadItem item, DownloadContext ctx, Uri url, SafeFileHandle handle, SpeedLimiter? limiter, Run run, CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            Segment? segment;
            lock (item.SegmentLock)
            {
                segment = item.Segments.FirstOrDefault(s => !s.Active && !s.Done) ?? Steal(item);
                if (segment is null) return;
                segment.Active = true;
            }
            try { await FetchSegmentAsync(item, ctx, url, segment, handle, limiter, run, ct); }
            catch (ServerBusyException) { return; }
            finally { lock (item.SegmentLock) segment.Active = false; }
        }
        ct.ThrowIfCancellationRequested();
    }

    /// Splits the active segment with the most bytes left; the caller takes the upper half.
    static Segment? Steal(DownloadItem item)
    {
        var victim = item.Segments.Where(s => s.Active && s.Remaining >= 2 * MinSegment).MaxBy(s => s.Remaining);
        if (victim is null) return null;
        var mid = victim.Position + victim.Remaining / 2;
        var upper = new Segment { Start = mid, End = victim.End };
        victim.End = mid - 1;
        item.Segments.Insert(item.Segments.IndexOf(victim) + 1, upper);
        return upper;
    }

    async Task FetchSegmentAsync(DownloadItem item, DownloadContext ctx, Uri url, Segment segment, SafeFileHandle handle, SpeedLimiter? limiter, Run run, CancellationToken ct)
    {
        var attempt = 0;
        var buffer = ArrayPool<byte>.Shared.Rent(BufferSize);
        try
        {
            while (true)
            {
                long from, to;
                lock (item.SegmentLock) { if (segment.Done) return; from = segment.Position; to = segment.End; }
                using var read = CancellationTokenSource.CreateLinkedTokenSource(ct);
                try
                {
                    using var request = ctx.Request(item, url);
                    request.Headers.Range = new RangeHeaderValue(from, to);
                    if (IfRange(item.Validator) is { } condition) request.Headers.IfRange = condition;
                    read.CancelAfter(StallTimeout);
                    using var response = await ctx.Http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, read.Token);
                    if (response.StatusCode == HttpStatusCode.OK) throw new RangeLostException();
                    if (response.StatusCode is HttpStatusCode.TooManyRequests or HttpStatusCode.ServiceUnavailable)
                    {
                        // The server caps connections per client: retire this one while others keep working,
                        // so the download settles at whatever the server allows (as IDM does).
                        if (Interlocked.Decrement(ref run.LiveWorkers) > 0) throw new ServerBusyException();
                        Interlocked.Increment(ref run.LiveWorkers);
                        if (++attempt > MaxRetries) throw DownloadException.ForStatus((int)response.StatusCode);
                        var wait = response.Headers.RetryAfter?.Delta ?? TimeSpan.FromSeconds(Math.Min(20, Math.Pow(2, attempt)));
                        if (wait > TimeSpan.FromSeconds(60)) wait = TimeSpan.FromSeconds(60);
                        item.Status = $"Server is limiting connections; retrying in {Math.Ceiling(wait.TotalSeconds)}s";
                        await Task.Delay(wait, ct);
                        item.Status = "Downloading";
                        continue;
                    }
                    if (!response.IsSuccessStatusCode) throw DownloadException.ForStatus((int)response.StatusCode);
                    await using var stream = await response.Content.ReadAsStreamAsync(read.Token);
                    while (true)
                    {
                        read.CancelAfter(StallTimeout);
                        var count = await stream.ReadAsync(buffer.AsMemory(0, BufferSize), read.Token);
                        if (count == 0) break;
                        long offset;
                        int take;
                        lock (item.SegmentLock)
                        {
                            offset = segment.Position;
                            take = (int)Math.Clamp(segment.End - offset + 1, 0, count);
                        }
                        if (take > 0)
                        {
                            await RandomAccess.WriteAsync(handle, buffer.AsMemory(0, take), offset, ct);
                            lock (item.SegmentLock) segment.Downloaded += take;
                        }
                        attempt = 0;
                        await ctx.ThrottleAsync(limiter, count, ct);
                        // Another connection took over the rest of this range.
                        if (take < count) return;
                        lock (item.SegmentLock) if (segment.Done) return;
                    }
                    lock (item.SegmentLock) if (segment.Done) return;
                    throw new IOException("The server closed the connection early.");
                }
                catch (Exception e) when (!ct.IsCancellationRequested && IsTransient(e))
                {
                    if (++attempt > MaxRetries)
                        throw new DownloadException("Connection kept failing: " + Describe(e), retryable: true, e);
                    await Task.Delay(TimeSpan.FromSeconds(Math.Min(20, Math.Pow(2, attempt - 1))), ct);
                }
            }
        }
        finally { ArrayPool<byte>.Shared.Return(buffer); }
    }

    static async Task SingleStreamAsync(DownloadItem item, DownloadContext ctx, HttpResponseMessage response, SpeedLimiter? limiter, CancellationToken ct)
    {
        item.State = DownloadState.Downloading;
        item.Status = item.TotalBytes > 0 ? "Downloading (server allows one connection)" : "Downloading (size unknown)";
        item.ActiveConnections = 1;
        var segment = new Segment { Start = 0, End = Math.Max(0, item.TotalBytes - 1) };
        lock (item.SegmentLock) { item.Segments.Clear(); if (item.TotalBytes > 0) item.Segments.Add(segment); }

        var buffer = ArrayPool<byte>.Shared.Rent(BufferSize);
        try
        {
            await using var file = new FileStream(item.PartPath!, FileMode.Create, FileAccess.Write, FileShare.Read, BufferSize, useAsync: true);
            using var read = CancellationTokenSource.CreateLinkedTokenSource(ct);
            await using var stream = await response.Content.ReadAsStreamAsync(ct);
            long written = 0;
            while (true)
            {
                read.CancelAfter(StallTimeout);
                int count;
                try { count = await stream.ReadAsync(buffer.AsMemory(0, BufferSize), read.Token); }
                catch (OperationCanceledException) when (!ct.IsCancellationRequested)
                { throw new DownloadException("The server stopped sending data.", retryable: true); }
                if (count == 0) break;
                await file.WriteAsync(buffer.AsMemory(0, count), ct);
                written += count;
                lock (item.SegmentLock) segment.Downloaded = written;
                item.DownloadedBytes = written;
                await ctx.ThrottleAsync(limiter, count, ct);
            }
            if (item.TotalBytes > 0 && written < item.TotalBytes)
                throw new DownloadException("The server closed the connection early.", retryable: true);
            item.TotalBytes = written;
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buffer);
            item.ActiveConnections = 0;
        }
    }

    static async Task MonitorAsync(DownloadItem item, DownloadContext ctx, CancellationToken ct)
    {
        var lastCheckpoint = DateTime.UtcNow;
        while (!ct.IsCancellationRequested)
        {
            await Task.Delay(250, ct);
            UpdateProgress(item);
            if (DateTime.UtcNow - lastCheckpoint > TimeSpan.FromSeconds(2))
            {
                ctx.Checkpoint(item);
                lastCheckpoint = DateTime.UtcNow;
            }
        }
    }

    static void UpdateProgress(DownloadItem item)
    {
        lock (item.SegmentLock)
        {
            item.DownloadedBytes = item.Segments.Sum(s => s.Downloaded);
            item.ActiveConnections = item.Segments.Count(s => s.Active);
        }
    }

    static void Finish(DownloadItem item)
    {
        item.State = DownloadState.Saving;
        item.Status = "Saving";
        var final = FileNaming.MoveToUnused(item.PartPath!, item.Folder, item.FileName);
        item.LocalPath = final;
        item.FileName = Path.GetFileName(final);
        item.PartPath = null;
        if (item.TotalBytes < 0) item.TotalBytes = new FileInfo(final).Length;
        item.DownloadedBytes = item.TotalBytes;
    }

    static RangeConditionHeaderValue? IfRange(string? validator)
    {
        if (string.IsNullOrEmpty(validator)) return null;
        // Weak ETags are not allowed in If-Range.
        if (validator.StartsWith("W/")) return null;
        if (validator.StartsWith('"')) return new RangeConditionHeaderValue(new EntityTagHeaderValue(validator));
        return DateTimeOffset.TryParse(validator, out var date) ? new RangeConditionHeaderValue(date) : null;
    }

    static bool IsTransient(Exception e) => e switch
    {
        DownloadException d => d.Retryable,
        RangeLostException => false,
        HttpRequestException or IOException or OperationCanceledException or TimeoutException => true,
        _ => false,
    };

    static string Describe(Exception e) => e is OperationCanceledException ? "the server stopped responding" : e.Message;

    /// Sparse preallocation, so writing a far segment first does not zero-fill the gap.
    static void Preallocate(string path, long length)
    {
        using var handle = File.OpenHandle(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.Read);
        if (OperatingSystem.IsWindows()) DeviceIoControl(handle, FsctlSetSparse, 0, 0, 0, 0, out _, 0);
        if (RandomAccess.GetLength(handle) != length) RandomAccess.SetLength(handle, length);
    }

    internal static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
            // HLS keeps its finished segments in a work folder.
            else if (Directory.Exists(path)) Directory.Delete(path, recursive: true);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    const uint FsctlSetSparse = 0x000900C4;

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(SafeFileHandle device, uint code, nint inBuffer, uint inSize, nint outBuffer, uint outSize, out uint returned, nint overlapped);
}

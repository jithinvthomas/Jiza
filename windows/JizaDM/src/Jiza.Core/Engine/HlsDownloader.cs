using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Jiza.Core.Model;

namespace Jiza.Core.Engine;

/// HLS (.m3u8) streams: picks the best variant, fetches segments in parallel, decrypts AES-128 and joins them.
/// Each finished segment is kept in a hidden work folder, so pausing and resuming skips what is already done.
public sealed partial class HlsDownloader : IDownloader
{
    public DownloadKind Kind => DownloadKind.Hls;

    public sealed record Variant(Uri Uri, long Bandwidth, int Height);
    public sealed record SegmentRef(int Index, Uri Uri, KeyRef? Key, long Sequence);
    public sealed record KeyRef(Uri Uri, byte[]? Iv);
    public sealed record MediaPlaylist(IReadOnlyList<SegmentRef> Segments, Uri? InitMap, bool Ended);

    public static string OutputName(Uri url, bool ffmpeg)
    {
        var stem = Path.GetFileNameWithoutExtension(Uri.UnescapeDataString(url.AbsolutePath));
        if (string.IsNullOrWhiteSpace(stem) || stem is "index" or "master" or "playlist" or "chunklist")
            stem = "video-" + DateTime.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
        return FileNaming.Safe(stem) + (ffmpeg ? ".mp4" : ".ts");
    }

    public static IReadOnlyList<Variant> ParseMaster(string text, Uri baseUri)
    {
        var variants = new List<Variant>();
        var lines = text.Split('\n').Select(l => l.Trim()).ToArray();
        for (var i = 0; i < lines.Length; i++)
        {
            if (!lines[i].StartsWith("#EXT-X-STREAM-INF:")) continue;
            var attrs = Attributes(lines[i]);
            var uriLine = lines.Skip(i + 1).FirstOrDefault(l => l.Length > 0 && !l.StartsWith('#'));
            if (uriLine is null) continue;
            long.TryParse(attrs.GetValueOrDefault("BANDWIDTH"), out var bandwidth);
            var height = 0;
            if (attrs.GetValueOrDefault("RESOLUTION") is { } res && res.Split('x') is [_, var h]) int.TryParse(h, out height);
            variants.Add(new Variant(new Uri(baseUri, uriLine), bandwidth, height));
        }
        return variants;
    }

    public static MediaPlaylist ParseMedia(string text, Uri baseUri)
    {
        var segments = new List<SegmentRef>();
        KeyRef? key = null;
        Uri? map = null;
        long sequence = 0;
        var ended = false;
        foreach (var raw in text.Split('\n'))
        {
            var line = raw.Trim();
            if (line.Length == 0) continue;
            if (line.StartsWith("#EXT-X-MEDIA-SEQUENCE:")) long.TryParse(line["#EXT-X-MEDIA-SEQUENCE:".Length..], out sequence);
            else if (line.StartsWith("#EXT-X-KEY:"))
            {
                var attrs = Attributes(line);
                var method = attrs.GetValueOrDefault("METHOD", "NONE");
                if (method == "NONE") key = null;
                else if (method == "AES-128")
                {
                    byte[]? iv = null;
                    if (attrs.GetValueOrDefault("IV") is { } ivText) iv = Convert.FromHexString(ivText.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? ivText[2..] : ivText);
                    key = new KeyRef(new Uri(baseUri, attrs["URI"]), iv);
                }
                else throw new DownloadException("This stream is DRM-protected (" + method + ") and can't be downloaded.");
            }
            else if (line.StartsWith("#EXT-X-MAP:") && Attributes(line).GetValueOrDefault("URI") is { } mapUri) map = new Uri(baseUri, mapUri);
            else if (line.StartsWith("#EXT-X-ENDLIST")) ended = true;
            else if (!line.StartsWith('#'))
            {
                segments.Add(new SegmentRef(segments.Count, new Uri(baseUri, line), key, sequence));
                sequence++;
            }
        }
        return new MediaPlaylist(segments, map, ended);
    }

    static Dictionary<string, string> Attributes(string line)
    {
        var body = line[(line.IndexOf(':') + 1)..];
        return AttributePattern().Matches(body).ToDictionary(m => m.Groups[1].Value, m => m.Groups[2].Value.Trim('"'));
    }

    [GeneratedRegex("([A-Z0-9-]+)=(\"[^\"]*\"|[^,]*)")]
    private static partial Regex AttributePattern();

    public async Task RunAsync(DownloadItem item, DownloadContext ctx, CancellationToken ct)
    {
        item.State = DownloadState.Connecting;
        item.Status = "Reading stream playlist";
        var playlistUri = new Uri(item.MediaFormat is { } chosen && Uri.TryCreate(chosen, UriKind.Absolute, out _) ? chosen : item.Url);
        var text = await GetTextAsync(item, ctx, playlistUri, ct);
        if (text.Contains("#EXT-X-STREAM-INF"))
        {
            var best = ParseMaster(text, playlistUri).MaxBy(v => (v.Height, v.Bandwidth))
                ?? throw new DownloadException("The stream playlist lists no playable variants.");
            playlistUri = best.Uri;
            text = await GetTextAsync(item, ctx, playlistUri, ct);
        }
        var playlist = ParseMedia(text, playlistUri);
        if (playlist.Segments.Count == 0) throw new DownloadException("The stream playlist has no segments.");

        var ffmpeg = ctx.Tools.Ffmpeg;
        if (string.IsNullOrWhiteSpace(item.FileName)) item.FileName = OutputName(new Uri(item.Url), ffmpeg is not null);
        if (playlist.InitMap is not null) item.FileName = Path.ChangeExtension(item.FileName, ".mp4");
        Directory.CreateDirectory(item.Folder);
        var work = Path.Combine(item.Folder, "." + item.Id.ToString("N") + ".hls");
        Directory.CreateDirectory(work);
        File.SetAttributes(work, File.GetAttributes(work) | FileAttributes.Hidden);
        item.PartPath = work;
        item.Resumable = true;

        var keys = new Dictionary<Uri, byte[]>();
        foreach (var keyUri in playlist.Segments.Select(s => s.Key?.Uri).OfType<Uri>().Distinct())
            keys[keyUri] = await GetBytesAsync(item, ctx, keyUri, null, ct);

        var total = playlist.Segments.Count;
        var done = playlist.Segments.Count(s => File.Exists(SegmentPath(work, s.Index)));
        long bytes = playlist.Segments.Where(s => File.Exists(SegmentPath(work, s.Index))).Sum(s => new FileInfo(SegmentPath(work, s.Index)).Length);
        item.State = DownloadState.Downloading;
        item.Status = playlist.Ended ? "Downloading stream" : "Recording live stream (current segments)";
        item.ProgressOverride = (double)done / total;
        item.DownloadedBytes = bytes;
        var limiter = item.SpeedLimit > 0 ? new SpeedLimiter(item.SpeedLimit) : null;

        var options = new ParallelOptions { MaxDegreeOfParallelism = Math.Clamp(item.Connections, 1, 32), CancellationToken = ct };
        item.ActiveConnections = options.MaxDegreeOfParallelism;
        try
        {
            await Parallel.ForEachAsync(playlist.Segments, options, async (segment, token) =>
            {
                var path = SegmentPath(work, segment.Index);
                if (File.Exists(path)) return;
                var data = await GetBytesAsync(item, ctx, segment.Uri, limiter, token);
                if (segment.Key is { } key) data = Decrypt(data, keys[key.Uri], key.Iv ?? SequenceIv(segment.Sequence));
                await File.WriteAllBytesAsync(path + ".tmp", data, token);
                File.Move(path + ".tmp", path, overwrite: true);
                item.DownloadedBytes = Interlocked.Add(ref bytes, data.Length);
                item.ProgressOverride = (double)Interlocked.Increment(ref done) / total;
                ctx.Checkpoint(item);
            });
        }
        finally { item.ActiveConnections = 0; }

        item.State = DownloadState.Saving;
        item.Status = "Joining segments";
        var joined = Path.Combine(work, playlist.InitMap is null ? "joined.ts" : "joined.mp4");
        await using (var output = new FileStream(joined, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 20, useAsync: true))
        {
            if (playlist.InitMap is { } map) await output.WriteAsync(await GetBytesAsync(item, ctx, map, null, ct), ct);
            foreach (var segment in playlist.Segments)
            {
                await using var input = File.OpenRead(SegmentPath(work, segment.Index));
                await input.CopyToAsync(output, ct);
            }
        }

        string? final = null;
        if (playlist.InitMap is null && ffmpeg is not null && item.FileName.EndsWith(".mp4", StringComparison.OrdinalIgnoreCase))
        {
            item.Status = "Converting to MP4";
            var target = FileNaming.Reserve(item.Folder, item.FileName);
            if (await RemuxAsync(ffmpeg, joined, target, ct)) final = target;
            else HttpDownloader.TryDelete(target);
        }
        final ??= FileNaming.MoveToUnused(joined, item.Folder,
            playlist.InitMap is null ? Path.ChangeExtension(item.FileName, ".ts") : item.FileName);
        Directory.Delete(work, recursive: true);
        item.PartPath = null;
        item.LocalPath = final;
        item.FileName = Path.GetFileName(final);
        item.TotalBytes = item.DownloadedBytes = new FileInfo(final).Length;
    }

    static string SegmentPath(string work, int index) => Path.Combine(work, index.ToString("D6", CultureInfo.InvariantCulture) + ".seg");

    static byte[] SequenceIv(long sequence)
    {
        var iv = new byte[16];
        for (var i = 0; i < 8; i++) iv[15 - i] = (byte)(sequence >> (8 * i));
        return iv;
    }

    public static byte[] Decrypt(byte[] data, byte[] key, byte[] iv)
    {
        using var aes = Aes.Create();
        aes.Key = key;
        return aes.DecryptCbc(data, iv, PaddingMode.PKCS7);
    }

    static async Task<bool> RemuxAsync(string ffmpeg, string input, string output, CancellationToken ct)
    {
        var info = new ProcessStartInfo(ffmpeg) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true };
        foreach (var a in new[] { "-y", "-loglevel", "error", "-i", input, "-c", "copy", "-bsf:a", "aac_adtstoasc", "-movflags", "+faststart", output })
            info.ArgumentList.Add(a);
        using var process = Process.Start(info);
        if (process is null) return false;
        var drain = process.StandardError.ReadToEndAsync(ct);
        try { await process.WaitForExitAsync(ct); }
        catch (OperationCanceledException) { process.Kill(true); throw; }
        await drain;
        if (process.ExitCode == 0 && File.Exists(output)) return true;
        HttpDownloader.TryDelete(output);
        return false;
    }

    static async Task<string> GetTextAsync(DownloadItem item, DownloadContext ctx, Uri uri, CancellationToken ct) =>
        System.Text.Encoding.UTF8.GetString(await GetBytesAsync(item, ctx, uri, null, ct));

    static async Task<byte[]> GetBytesAsync(DownloadItem item, DownloadContext ctx, Uri uri, SpeedLimiter? limiter, CancellationToken ct)
    {
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                using var request = ctx.Request(item, uri);
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
                timeout.CancelAfter(TimeSpan.FromSeconds(60));
                using var response = await ctx.Http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
                if (!response.IsSuccessStatusCode) throw DownloadException.ForStatus((int)response.StatusCode);
                var data = await response.Content.ReadAsByteArrayAsync(timeout.Token);
                await ctx.ThrottleAsync(limiter, data.Length, ct);
                return data;
            }
            catch (Exception e) when (!ct.IsCancellationRequested && attempt < 6 && e is HttpRequestException or IOException or OperationCanceledException or DownloadException { Retryable: true })
            {
                await Task.Delay(TimeSpan.FromSeconds(Math.Min(10, attempt * 2)), ct);
            }
        }
    }
}

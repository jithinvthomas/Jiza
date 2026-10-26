using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using Jiza.Core.Model;

namespace Jiza.Core.Engine;

public sealed record MediaProbe(string Title, string FileName, IReadOnlyList<MediaChoice> Choices);

/// Wraps yt-dlp, which extracts the real video URLs from 1000+ sites (YouTube, Vimeo, X, TikTok...) and DASH manifests.
public static class YtDlp
{
    public static async Task<string> EnsureAsync(DownloadContext ctx, DownloadItem? item, CancellationToken ct)
    {
        if (ctx.Tools.YtDlp is { } path) return path;
        if (item is not null) item.Status = "Installing video support (yt-dlp)";
        return await ctx.Tools.InstallYtDlpAsync(ctx.Http, null, ct);
    }

    public static async Task<MediaProbe> ProbeAsync(string url, IReadOnlyDictionary<string, string> headers, DownloadContext ctx, CancellationToken ct)
    {
        var exe = await EnsureAsync(ctx, null, ct);
        var args = new List<string> { "-J", "--no-playlist", "--no-warnings" };
        AddHeaders(args, headers);
        args.Add(url);
        var (code, output, error) = await RunAsync(exe, args, null, ct);
        if (code != 0) throw new DownloadException(CleanError(error) ?? "No video was found at this address.");

        using var json = JsonDocument.Parse(output);
        var root = json.RootElement;
        var title = root.TryGetProperty("title", out var t) ? t.GetString() ?? "video" : "video";
        var hasFfmpeg = ctx.Tools.Ffmpeg is not null;
        var choices = new List<MediaChoice>();
        var heights = new SortedSet<int>(Comparer<int>.Create((a, b) => b.CompareTo(a)));
        long bestAudio = 0;
        if (root.TryGetProperty("formats", out var formats))
        {
            foreach (var f in formats.EnumerateArray())
            {
                var vcodec = f.TryGetProperty("vcodec", out var v) ? v.GetString() : null;
                var acodec = f.TryGetProperty("acodec", out var a) ? a.GetString() : null;
                var size = Size(f);
                if (vcodec == "none" && acodec != "none") bestAudio = Math.Max(bestAudio, size);
                if (vcodec is not null and not "none" && f.TryGetProperty("height", out var h) && h.ValueKind == JsonValueKind.Number)
                {
                    // Without ffmpeg, only formats that already contain audio can be used.
                    if (!hasFfmpeg && acodec == "none") continue;
                    heights.Add(h.GetInt32());
                }
            }
        }
        string Best(int? height)
        {
            var limit = height is null ? "" : $"[height<={height}]";
            return hasFfmpeg ? $"bv*{limit}+ba/b{limit}" : $"b{limit}";
        }
        choices.Add(new MediaChoice("Best quality", Best(null), -1));
        foreach (var h in heights.Where(h => h >= 144).Take(8)) choices.Add(new MediaChoice($"{h}p", Best(h), -1));
        choices.Add(new MediaChoice("Audio only", hasFfmpeg ? "ba/b" : "ba[acodec!=none]/b", bestAudio > 0 ? bestAudio : -1));
        if (hasFfmpeg) choices.Add(new MediaChoice("Audio only (MP3)", "ba/b|mp3", -1));
        var ext = root.TryGetProperty("ext", out var e) ? e.GetString() ?? "mp4" : "mp4";
        return new MediaProbe(title, FileNaming.Safe(title) + "." + ext, choices);
    }

    static long Size(JsonElement f)
    {
        foreach (var key in new[] { "filesize", "filesize_approx" })
            if (f.TryGetProperty(key, out var s) && s.ValueKind == JsonValueKind.Number) return s.GetInt64();
        return 0;
    }

    public static void AddHeaders(List<string> args, IReadOnlyDictionary<string, string> headers)
    {
        foreach (var (key, value) in headers)
        {
            if (key.Equals("Referer", StringComparison.OrdinalIgnoreCase)) { args.Add("--referer"); args.Add(value); }
            else if (key.Equals("User-Agent", StringComparison.OrdinalIgnoreCase)) { args.Add("--user-agent"); args.Add(value); }
            else { args.Add("--add-header"); args.Add($"{key}:{value}"); }
        }
    }

    public static async Task<(int Code, string Output, string Error)> RunAsync(string exe, IEnumerable<string> args, Action<string>? onLine, CancellationToken ct)
    {
        var info = new ProcessStartInfo(exe)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = System.Text.Encoding.UTF8,
            StandardErrorEncoding = System.Text.Encoding.UTF8,
        };
        foreach (var a in args) info.ArgumentList.Add(a);
        info.Environment["PYTHONIOENCODING"] = "utf-8";
        using var process = Process.Start(info) ?? throw new DownloadException("Could not start yt-dlp.");
        var output = new System.Text.StringBuilder();
        var error = new System.Text.StringBuilder();
        var readOut = Task.Run(async () =>
        {
            while (await process.StandardOutput.ReadLineAsync() is { } line) { output.AppendLine(line); onLine?.Invoke(line); }
        });
        var readErr = Task.Run(async () =>
        {
            while (await process.StandardError.ReadLineAsync() is { } line) { error.AppendLine(line); onLine?.Invoke(line); }
        });
        try { await process.WaitForExitAsync(ct); }
        catch (OperationCanceledException)
        {
            try { process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
            throw;
        }
        await Task.WhenAll(readOut, readErr);
        return (process.ExitCode, output.ToString(), error.ToString());
    }

    public static string? CleanError(string stderr) =>
        stderr.Split('\n').Select(l => l.Trim()).LastOrDefault(l => l.StartsWith("ERROR:"))?["ERROR:".Length..].Trim();

    public static bool TryParseProgress(string line, out long downloaded, out long total, out double speed, out double? fraction)
    {
        downloaded = 0; total = -1; speed = 0; fraction = null;
        if (!line.StartsWith("JZP ")) return false;
        var parts = line[4..].Split(' ');
        if (parts.Length < 6) return false;
        static double Num(string s) => double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var d) ? d : -1;
        downloaded = (long)Math.Max(0, Num(parts[0]));
        var exact = Num(parts[1]);
        var estimate = Num(parts[2]);
        total = (long)(exact > 0 ? exact : estimate);
        speed = Math.Max(0, Num(parts[3]));
        var index = Num(parts[4]);
        var count = Num(parts[5]);
        if (total <= 0 && index >= 0 && count > 0) fraction = Math.Clamp(index / count, 0, 1);
        return true;
    }
}

public sealed class MediaDownloader : IDownloader
{
    public DownloadKind Kind => DownloadKind.Media;

    public async Task RunAsync(DownloadItem item, DownloadContext ctx, CancellationToken ct)
    {
        item.State = DownloadState.Connecting;
        var exe = await YtDlp.EnsureAsync(ctx, item, ct);
        item.Status = "Finding video";
        Directory.CreateDirectory(item.Folder);

        var selector = item.MediaFormat ?? (ctx.Tools.Ffmpeg is null ? "b" : "bv*+ba/b");
        var audioToMp3 = selector.EndsWith("|mp3");
        if (audioToMp3) selector = selector[..^4];

        var args = new List<string>
        {
            "--no-playlist", "--newline", "--no-colors", "--continue", "--progress",
            // Parallel fragments for HLS/DASH and chunked HTTP to dodge per-connection throttling.
            "-N", Math.Clamp(item.Connections, 1, 32).ToString(CultureInfo.InvariantCulture),
            "--http-chunk-size", "10M",
            "-f", selector,
            "-P", item.Folder,
            "-o", "%(title).150B [%(id)s].%(ext)s",
            "--progress-template", "download:JZP %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s %(progress.speed)s %(progress.fragment_index)s %(progress.fragment_count)s",
            "--print", "after_move:JZF %(filepath)s",
        };
        if (ctx.Tools.Ffmpeg is { } ffmpeg) { args.Add("--ffmpeg-location"); args.Add(ffmpeg); }
        if (audioToMp3) { args.Add("-x"); args.Add("--audio-format"); args.Add("mp3"); }
        var limit = new[] { item.SpeedLimit, ctx.Settings.GlobalSpeedLimit }.Where(l => l > 0).DefaultIfEmpty(0).Min();
        if (limit > 0) { args.Add("--limit-rate"); args.Add(limit.ToString(CultureInfo.InvariantCulture)); }
        YtDlp.AddHeaders(args, item.Headers);
        args.Add(item.Url);

        string? finalPath = null;
        var (code, _, error) = await YtDlp.RunAsync(exe, args, line =>
        {
            if (YtDlp.TryParseProgress(line, out var done, out var total, out _, out var fraction))
            {
                item.State = DownloadState.Downloading;
                item.Status = "Downloading";
                if (total > 0) item.TotalBytes = total;
                item.DownloadedBytes = done;
                item.ProgressOverride = fraction;
            }
            else if (line.StartsWith("JZF ")) finalPath = line[4..].Trim();
            else if (line.StartsWith("[Merger]") || line.StartsWith("[ExtractAudio]") || line.StartsWith("[VideoConvertor]"))
            {
                item.State = DownloadState.Saving;
                item.Status = "Merging video and audio";
            }
        }, ct);
        if (code != 0) throw new DownloadException(YtDlp.CleanError(error) ?? "yt-dlp could not download this video.", retryable: true);
        if (finalPath is not null && File.Exists(finalPath))
        {
            item.LocalPath = finalPath;
            item.FileName = Path.GetFileName(finalPath);
            item.TotalBytes = item.DownloadedBytes = new FileInfo(finalPath).Length;
        }
        item.Resumable = true;
    }
}

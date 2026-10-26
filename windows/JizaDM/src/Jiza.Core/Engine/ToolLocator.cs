using System.IO.Compression;

namespace Jiza.Core.Engine;

/// Finds or installs the helper tools: yt-dlp (video sites, DASH) and ffmpeg (merging and remuxing).
public sealed class ToolLocator
{
    public const string YtDlpUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe";
    public const string FfmpegUrl = "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip";

    public string ToolsFolder { get; }

    public ToolLocator(string? toolsFolder = null) =>
        ToolsFolder = toolsFolder ?? Path.Combine(Store.DefaultDataFolder, "tools");

    public string? YtDlp => Find("yt-dlp.exe");
    public string? Ffmpeg => Find("ffmpeg.exe");

    string? Find(string exe)
    {
        foreach (var dir in new[] { ToolsFolder, AppContext.BaseDirectory })
        {
            var path = Path.Combine(dir, exe);
            if (File.Exists(path)) return path;
        }
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                var path = Path.Combine(dir.Trim(), exe);
                if (File.Exists(path)) return path;
            }
            catch (ArgumentException) { }
        }
        return null;
    }

    public async Task<string> InstallYtDlpAsync(HttpClient http, IProgress<double>? progress, CancellationToken ct)
    {
        Directory.CreateDirectory(ToolsFolder);
        var target = Path.Combine(ToolsFolder, "yt-dlp.exe");
        await DownloadAsync(http, YtDlpUrl, target + ".tmp", progress, ct);
        File.Move(target + ".tmp", target, overwrite: true);
        return target;
    }

    public async Task<string> InstallFfmpegAsync(HttpClient http, IProgress<double>? progress, CancellationToken ct)
    {
        Directory.CreateDirectory(ToolsFolder);
        var zip = Path.Combine(ToolsFolder, "ffmpeg.zip");
        await DownloadAsync(http, FfmpegUrl, zip, progress, ct);
        try
        {
            using var archive = ZipFile.OpenRead(zip);
            foreach (var entry in archive.Entries)
            {
                if (entry.Name is "ffmpeg.exe" or "ffprobe.exe")
                    entry.ExtractToFile(Path.Combine(ToolsFolder, entry.Name), overwrite: true);
            }
        }
        finally { File.Delete(zip); }
        return Path.Combine(ToolsFolder, "ffmpeg.exe");
    }

    static async Task DownloadAsync(HttpClient http, string url, string target, IProgress<double>? progress, CancellationToken ct)
    {
        using var response = await http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct);
        response.EnsureSuccessStatusCode();
        var total = response.Content.Headers.ContentLength ?? -1;
        await using var source = await response.Content.ReadAsStreamAsync(ct);
        await using var file = File.Create(target);
        var buffer = new byte[256 * 1024];
        long done = 0;
        int read;
        while ((read = await source.ReadAsync(buffer, ct)) > 0)
        {
            await file.WriteAsync(buffer.AsMemory(0, read), ct);
            done += read;
            if (total > 0) progress?.Report((double)done / total);
        }
    }
}

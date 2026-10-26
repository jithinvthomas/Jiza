namespace Jiza.Core;

/// Ported from Jiza's BrowserDownloadPolicy: which links and responses count as downloads.
public static class DownloadPolicy
{
    public static readonly IReadOnlySet<string> Extensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "mp4", "m4v", "mov", "mkv", "webm", "avi", "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "zip", "rar", "7z", "gz",
        "tar", "pdf", "epub", "dmg", "exe", "msi", "apk", "ipa", "iso", "torrent", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        // Additions for a desktop download manager.
        "bz2", "xz", "zst", "img", "bin", "wmv", "flv", "3gp", "ts", "m3u8", "mpd", "wma", "msix", "appx", "jar", "deb", "rpm", "csv",
    };

    static readonly string[] DownloadMimes =
    [
        "application/octet-stream", "application/x-bittorrent", "application/zip", "application/x-rar-compressed",
        "application/pdf", "application/x-7z-compressed", "application/x-msdownload", "application/x-msi",
        "application/vnd.android.package-archive", "application/x-iso9660-image", "application/gzip",
    ];

    static readonly Dictionary<string, string> MimeExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ["video/mp4"] = "mp4", ["video/webm"] = "webm", ["video/x-matroska"] = "mkv", ["video/quicktime"] = "mov",
        ["audio/mpeg"] = "mp3", ["audio/mp4"] = "m4a", ["audio/aac"] = "aac", ["audio/wav"] = "wav", ["audio/flac"] = "flac",
        ["audio/ogg"] = "ogg", ["application/pdf"] = "pdf", ["application/zip"] = "zip", ["application/x-rar-compressed"] = "rar",
        ["application/x-7z-compressed"] = "7z", ["application/gzip"] = "gz", ["application/x-bittorrent"] = "torrent",
        ["application/x-msdownload"] = "exe", ["application/vnd.android.package-archive"] = "apk", ["application/epub+zip"] = "epub",
        ["application/vnd.apple.mpegurl"] = "m3u8", ["application/x-mpegurl"] = "m3u8", ["application/dash+xml"] = "mpd",
        ["image/jpeg"] = "jpg", ["image/png"] = "png", ["image/gif"] = "gif", ["image/webp"] = "webp", ["text/plain"] = "txt",
    };

    public static bool IsWebUrl(Uri? url) => url is { IsAbsoluteUri: true } && (url.Scheme == Uri.UriSchemeHttp || url.Scheme == Uri.UriSchemeHttps);

    public static string ExtensionOf(Uri url) => Path.GetExtension(url.AbsolutePath).TrimStart('.').ToLowerInvariant();

    public static bool IsFileLink(Uri url) => Extensions.Contains(ExtensionOf(url));

    public static bool ShouldDownload(string? mime, string? disposition, bool mainFrame, bool enabled)
    {
        if (disposition?.Contains("attachment", StringComparison.OrdinalIgnoreCase) == true) return true;
        if (!enabled || !mainFrame) return false;
        var value = Mime(mime);
        return value.StartsWith("video/") || value.StartsWith("audio/") || DownloadMimes.Contains(value);
    }

    public static string? ExtensionForMime(string? mime) => MimeExtensions.TryGetValue(Mime(mime), out var ext) ? ext : null;

    /// A link the clipboard monitor should offer to download.
    public static bool IsMonitoredLink(string? text, IReadOnlySet<string>? extensions = null)
    {
        if (string.IsNullOrWhiteSpace(text)) return false;
        text = text.Trim();
        if (text.Contains('\n') || text.Length > 8192) return false;
        if (text.StartsWith("magnet:?", StringComparison.OrdinalIgnoreCase)) return true;
        if (!Uri.TryCreate(text, UriKind.Absolute, out var url)) return false;
        if (url.Scheme == "ftp") return true;
        return IsWebUrl(url) && (extensions ?? Extensions).Contains(ExtensionOf(url));
    }

    static string Mime(string? mime) => (mime ?? "").Split(';')[0].Trim().ToLowerInvariant();
}

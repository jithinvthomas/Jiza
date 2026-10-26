namespace Jiza.Core.Model;

public static class Categories
{
    public const string Video = "Video", Music = "Music", Documents = "Documents", Compressed = "Compressed",
        Programs = "Programs", Torrents = "Torrents", Other = "Other";

    public static readonly string[] All = [Video, Music, Documents, Compressed, Programs, Torrents, Other];

    static readonly Dictionary<string, string> ByExtension = new(StringComparer.OrdinalIgnoreCase);

    static Categories()
    {
        void Map(string category, params string[] exts) { foreach (var e in exts) ByExtension[e] = category; }
        Map(Video, "mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "flv", "3gp", "ts", "m3u8", "mpd");
        Map(Music, "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "wma");
        Map(Documents, "pdf", "epub", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv", "rtf", "odt");
        Map(Compressed, "zip", "rar", "7z", "gz", "tar", "bz2", "xz", "zst", "iso", "img");
        Map(Programs, "exe", "msi", "msix", "appx", "dmg", "apk", "ipa", "jar", "deb", "rpm", "bin");
        Map(Torrents, "torrent");
    }

    public static string For(string fileName, DownloadKind kind) => kind switch
    {
        DownloadKind.Torrent => Torrents,
        DownloadKind.Hls or DownloadKind.Media => Video,
        _ => ByExtension.GetValueOrDefault(Path.GetExtension(fileName).TrimStart('.'), Other),
    };
}

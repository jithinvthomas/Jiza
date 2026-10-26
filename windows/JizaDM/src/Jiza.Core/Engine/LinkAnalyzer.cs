using System.Net.Http.Headers;
using System.Web;
using Jiza.Core.Model;

namespace Jiza.Core.Engine;

public sealed record MediaChoice(string Label, string Selector, long EstimatedBytes);

public sealed record LinkInfo(DownloadKind Kind, string FileName, long Size, string? Mime, bool Resumable)
{
    public string? Note { get; init; }
    public string? Title { get; init; }
    public IReadOnlyList<MediaChoice> Choices { get; init; } = [];
}

/// Decides how a link is downloaded: a file, a stream playlist, a video page or a torrent.
public static class LinkAnalyzer
{
    static readonly string[] MediaSites =
    [
        "youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitch.tv", "tiktok.com", "instagram.com", "facebook.com",
        "fb.watch", "x.com", "twitter.com", "reddit.com", "soundcloud.com", "bilibili.com", "rumble.com", "streamable.com",
        "bandcamp.com", "mixcloud.com", "vk.com", "ok.ru", "linkedin.com", "pinterest.com", "kick.com", "9gag.com",
    ];

    public static DownloadKind GuessKind(string url)
    {
        url = url.Trim();
        if (url.StartsWith("magnet:", StringComparison.OrdinalIgnoreCase)) return DownloadKind.Torrent;
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return DownloadKind.Http;
        if (uri.Scheme is "ftp" or "ftps") return DownloadKind.Ftp;
        if (uri.IsFile && uri.AbsolutePath.EndsWith(".torrent", StringComparison.OrdinalIgnoreCase)) return DownloadKind.Torrent;
        return DownloadPolicy.ExtensionOf(uri) switch
        {
            "torrent" => DownloadKind.Torrent,
            "m3u8" => DownloadKind.Hls,
            "mpd" => DownloadKind.Media,
            _ when IsMediaSite(uri) => DownloadKind.Media,
            _ => DownloadKind.Http,
        };
    }

    public static bool IsMediaSite(Uri uri) =>
        MediaSites.Any(site => uri.Host.Equals(site, StringComparison.OrdinalIgnoreCase) || uri.Host.EndsWith("." + site, StringComparison.OrdinalIgnoreCase));

    public static async Task<LinkInfo> AnalyzeAsync(string url, IReadOnlyDictionary<string, string> headers, DownloadContext ctx, CancellationToken ct)
    {
        url = url.Trim();
        var kind = GuessKind(url);
        switch (kind)
        {
            case DownloadKind.Torrent when url.StartsWith("magnet:", StringComparison.OrdinalIgnoreCase):
                return new LinkInfo(kind, MagnetName(url) ?? "Torrent", -1, "application/x-bittorrent", true) { Note = "Magnet link. Files appear once peers send the metadata." };
            case DownloadKind.Torrent:
                return new LinkInfo(kind, FileNaming.Safe(Path.GetFileNameWithoutExtension(new Uri(url).AbsolutePath)), -1, "application/x-bittorrent", true);
            case DownloadKind.Ftp:
                return new LinkInfo(kind, FileNaming.Safe(Uri.UnescapeDataString(Path.GetFileName(new Uri(url).AbsolutePath))), await FtpDownloader.SizeAsync(new Uri(url), ct), null, true);
            case DownloadKind.Hls:
                return new LinkInfo(kind, HlsDownloader.OutputName(new Uri(url), ctx.Tools.Ffmpeg is not null), -1, "application/vnd.apple.mpegurl", true)
                    { Note = "Stream playlist. Segments download in parallel." };
            case DownloadKind.Media:
                return await AnalyzeMediaAsync(url, headers, ctx, ct, null);
        }

        var uri = new Uri(url);
        var item = new DownloadItem { Url = url };
        foreach (var (k, v) in headers) item.Headers[k] = v;
        using var request = ctx.Request(item, uri);
        request.Headers.Range = new RangeHeaderValue(0, null);
        using var response = await ctx.Http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
        if (!response.IsSuccessStatusCode) throw DownloadException.ForStatus((int)response.StatusCode);
        var finalUri = response.RequestMessage?.RequestUri ?? uri;
        var content = response.Content.Headers;
        var mime = content.ContentType?.MediaType?.ToLowerInvariant();
        var disposition = content.ContentDisposition?.ToString();
        var ranged = response.StatusCode == System.Net.HttpStatusCode.PartialContent && content.ContentRange?.Length is > 0;
        var size = ranged ? content.ContentRange!.Length!.Value : content.ContentLength ?? -1;

        switch (mime)
        {
            case "application/vnd.apple.mpegurl" or "application/x-mpegurl" or "audio/mpegurl":
                return new LinkInfo(DownloadKind.Hls, HlsDownloader.OutputName(finalUri, ctx.Tools.Ffmpeg is not null), -1, mime, true);
            case "application/dash+xml":
                return await AnalyzeMediaAsync(url, headers, ctx, ct, null);
            case "application/x-bittorrent":
                return new LinkInfo(DownloadKind.Torrent, FileNaming.FromResponse(finalUri, disposition, mime), size, mime, true);
            case "text/html" or "application/xhtml+xml" when disposition?.Contains("attachment", StringComparison.OrdinalIgnoreCase) != true:
                // A web page: look for a video on it, otherwise save the page itself (as Jiza's "Download page").
                var fallback = new LinkInfo(DownloadKind.Http, FileNaming.FromResponse(finalUri, disposition, mime), size, mime, ranged)
                    { Note = "This is a web page with no file or video Jiza can find. Downloading saves the page." };
                return await AnalyzeMediaAsync(url, headers, ctx, ct, fallback);
        }
        return new LinkInfo(DownloadKind.Http, FileNaming.FromResponse(finalUri, disposition, mime), size, mime, ranged)
        {
            Note = ranged ? null : "This server allows only one connection, so the download can't be accelerated or resumed.",
        };
    }

    static async Task<LinkInfo> AnalyzeMediaAsync(string url, IReadOnlyDictionary<string, string> headers, DownloadContext ctx, CancellationToken ct, LinkInfo? fallback)
    {
        try
        {
            var media = await YtDlp.ProbeAsync(url, headers, ctx, ct);
            return new LinkInfo(DownloadKind.Media, media.FileName, media.Choices.FirstOrDefault()?.EstimatedBytes ?? -1, null, true)
            {
                Title = media.Title,
                Choices = media.Choices,
                Note = ctx.Tools.Ffmpeg is null ? "Install ffmpeg in Options for the highest qualities (separate video and audio)." : null,
            };
        }
        catch (Exception e) when (fallback is not null && e is not OperationCanceledException)
        {
            return fallback;
        }
    }

    static string? MagnetName(string magnet)
    {
        var query = magnet.IndexOf('?') is var i and >= 0 ? magnet[(i + 1)..] : "";
        var name = HttpUtility.ParseQueryString(query)["dn"];
        return string.IsNullOrWhiteSpace(name) ? null : FileNaming.Safe(name);
    }
}

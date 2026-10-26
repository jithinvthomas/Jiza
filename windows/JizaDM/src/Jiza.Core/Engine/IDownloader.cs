using Jiza.Core.Model;

namespace Jiza.Core.Engine;

public interface IDownloader
{
    DownloadKind Kind { get; }
    /// Runs until the item completes. Throws OperationCanceledException when paused.
    Task RunAsync(DownloadItem item, DownloadContext context, CancellationToken ct);
}

public sealed class DownloadContext
{
    public required HttpClient Http { get; init; }
    public required DownloadSettings Settings { get; init; }
    public SpeedLimiter GlobalLimiter { get; init; } = new();
    public ToolLocator Tools { get; init; } = new();
    /// Persist the item's segment state; called periodically by downloaders.
    public Action<DownloadItem> Checkpoint { get; init; } = _ => { };

    public async ValueTask ThrottleAsync(SpeedLimiter? itemLimiter, int bytes, CancellationToken ct)
    {
        await GlobalLimiter.WaitAsync(bytes, ct);
        if (itemLimiter is not null) await itemLimiter.WaitAsync(bytes, ct);
    }

    public HttpRequestMessage Request(DownloadItem item, Uri url, HttpMethod? method = null)
    {
        var request = new HttpRequestMessage(method ?? HttpMethod.Get, url);
        if (!item.Headers.ContainsKey("User-Agent")) request.Headers.TryAddWithoutValidation("User-Agent", Settings.UserAgent);
        foreach (var (key, value) in item.Headers) request.Headers.TryAddWithoutValidation(key, value);
        return request;
    }
}

/// A failure the user can act on; the message is shown verbatim in the Status column.
public sealed class DownloadException(string message, bool retryable = false, Exception? inner = null) : Exception(message, inner)
{
    public bool Retryable { get; } = retryable;

    /// Ported from Jiza: non-2xx responses explain what to do next.
    public static DownloadException ForStatus(int code) => code switch
    {
        404 or 410 => new($"Server returned HTTP {code}. The file is no longer at this address."),
        416 => new("Server rejected the resume position. Restart the download."),
        429 => new("Server returned HTTP 429: too many requests from this computer. Wait a minute, then retry.", retryable: true),
        >= 500 => new($"Server returned HTTP {code}. Try again later.", retryable: true),
        _ => new($"Server returned HTTP {code}. Sign in or refresh the download link, then retry."),
    };
}

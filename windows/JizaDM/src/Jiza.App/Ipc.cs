using System.IO;
using System.IO.Pipes;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Jiza.Core.Queue;

namespace Jiza.App;

/// A link handed over by the browser extension, the command line, jiza:// or a second app instance.
public sealed class IncomingRequest
{
    /// "download" (a captured browser download), "link" (context menu / clipboard), "media", "batch", "show", "ping".
    public string Type { get; set; } = "link";
    public string? Url { get; set; }
    public string? Referrer { get; set; }
    public string? Cookies { get; set; }
    public string? UserAgent { get; set; }
    public string? FileName { get; set; }
    public string? Mime { get; set; }
    public long? FileSize { get; set; }
    public string? PageUrl { get; set; }
    public string? Title { get; set; }
    public List<IncomingRequest>? Items { get; set; }

    public static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public DownloadRequest ToDownloadRequest() => new(Url ?? "")
    {
        FileName = FileName,
        Referrer = Referrer ?? PageUrl,
        Cookies = Cookies,
        UserAgent = UserAgent,
        TotalBytes = FileSize ?? -1,
    };
}

/// Per-user named pipe between the running app and other Jiza processes.
public static class Ipc
{
    public static string PipeName { get; } = "JizaDM-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Environment.UserName)))[..16];

    public static async Task<bool> SendAsync(IncomingRequest request, TimeSpan timeout)
    {
        try
        {
            await using var pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.InOut, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
            using var cts = new CancellationTokenSource(timeout);
            await pipe.ConnectAsync(cts.Token);
            var writer = new StreamWriter(pipe, new UTF8Encoding(false)) { AutoFlush = true };
            await writer.WriteLineAsync(JsonSerializer.Serialize(request, IncomingRequest.Json));
            var reader = new StreamReader(pipe, Encoding.UTF8);
            return await reader.ReadLineAsync(cts.Token) == "ok";
        }
        catch (Exception e) when (e is IOException or TimeoutException or OperationCanceledException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    /// handle returns false to refuse a request (the browser then keeps its own download).
    public static async Task ServeAsync(Func<IncomingRequest, bool> handle, CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            var pipe = new NamedPipeServerStream(PipeName, PipeDirection.InOut, NamedPipeServerStream.MaxAllowedServerInstances,
                PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
            try { await pipe.WaitForConnectionAsync(ct); }
            catch (OperationCanceledException) { await pipe.DisposeAsync(); return; }
            _ = Task.Run(async () =>
            {
                await using (pipe)
                {
                    try
                    {
                        var reader = new StreamReader(pipe, Encoding.UTF8);
                        var line = await reader.ReadLineAsync(ct);
                        var request = line is null ? null : JsonSerializer.Deserialize<IncomingRequest>(line, IncomingRequest.Json);
                        var accepted = request is not null && handle(request);
                        var writer = new StreamWriter(pipe, new UTF8Encoding(false)) { AutoFlush = true };
                        await writer.WriteLineAsync(accepted ? "ok" : "refused");
                    }
                    catch (Exception e) when (e is IOException or JsonException or OperationCanceledException) { }
                }
            }, ct);
        }
    }
}

using System.Collections.Concurrent;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Jiza.Core.Tests;

/// Local Kestrel server with ranged, non-ranged, throttled, missing and HLS endpoints.
public sealed class TestServer : IAsyncLifetime
{
    public byte[] File { get; } = RandomNumberGenerator.GetBytes(12 * 1024 * 1024 + 12345);
    public byte[][] HlsSegments { get; } = Enumerable.Range(0, 6).Select(_ => RandomNumberGenerator.GetBytes(150_000)).ToArray();
    public byte[] HlsKey { get; } = RandomNumberGenerator.GetBytes(16);
    public ConcurrentQueue<(string Path, long From)> Requests { get; } = new();
    /// Bytes per 10 ms tick for /slow.bin.
    public int SlowChunk { get; set; } = 32 * 1024;
    public string BaseUrl { get; private set; } = "";
    WebApplication? _app;
    int _limitedActive;

    public async Task InitializeAsync()
    {
        var builder = WebApplication.CreateSlimBuilder();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        _app = builder.Build();
        _app.Use(async (context, next) =>
        {
            Requests.Enqueue((context.Request.Path, ParseRange(context.Request.Headers.Range.ToString())?.From ?? 0));
            await next();
        });
        _app.MapGet("/file.bin", () => Results.File(File, "application/octet-stream", "file.bin", enableRangeProcessing: true));
        _app.MapGet("/download", (HttpContext c) =>
        {
            c.Response.Headers.ContentDisposition = "attachment; filename*=UTF-8''report%20final.pdf";
            return Results.File(File, "application/pdf", enableRangeProcessing: true);
        });
        _app.MapGet("/norange.bin", async (HttpContext c) =>
        {
            c.Response.ContentType = "application/octet-stream";
            c.Response.ContentLength = File.Length;
            await c.Response.Body.WriteAsync(File);
        });
        _app.MapGet("/slow.bin", async (HttpContext c) =>
        {
            var range = ParseRange(c.Request.Headers.Range.ToString());
            long from = range?.From ?? 0, to = range?.To ?? File.Length - 1;
            c.Response.StatusCode = range is null ? 200 : 206;
            c.Response.Headers.AcceptRanges = "bytes";
            c.Response.Headers.ETag = "\"v1\"";
            if (range is not null) c.Response.Headers.ContentRange = $"bytes {from}-{to}/{File.Length}";
            c.Response.ContentLength = to - from + 1;
            try
            {
                for (var pos = from; pos <= to; pos += SlowChunk)
                {
                    var count = (int)Math.Min(SlowChunk, to - pos + 1);
                    await c.Response.Body.WriteAsync(File.AsMemory((int)pos, count), c.RequestAborted);
                    await Task.Delay(10, c.RequestAborted);
                }
            }
            catch (OperationCanceledException) { }
        });
        _app.MapGet("/limited.bin", async (HttpContext c) =>
        {
            // Like proof.ovh.net: at most 4 connections per client, extra ones get 429.
            if (Interlocked.Increment(ref _limitedActive) > 4)
            {
                Interlocked.Decrement(ref _limitedActive);
                c.Response.StatusCode = 429;
                return;
            }
            try
            {
                var range = ParseRange(c.Request.Headers.Range.ToString());
                long from = range?.From ?? 0, to = range?.To ?? File.Length - 1;
                c.Response.StatusCode = range is null ? 200 : 206;
                c.Response.Headers.AcceptRanges = "bytes";
                if (range is not null) c.Response.Headers.ContentRange = $"bytes {from}-{to}/{File.Length}";
                c.Response.ContentLength = to - from + 1;
                for (var pos = from; pos <= to; pos += 256 * 1024)
                {
                    await c.Response.Body.WriteAsync(File.AsMemory((int)pos, (int)Math.Min(256 * 1024, to - pos + 1)), c.RequestAborted);
                    await Task.Delay(5, c.RequestAborted);
                }
            }
            catch (OperationCanceledException) { }
            finally { Interlocked.Decrement(ref _limitedActive); }
        });
        _app.MapGet("/missing", () => Results.NotFound());
        _app.MapGet("/hls/master.m3u8", () => Results.Text(
            "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=500000,RESOLUTION=640x360\nlow.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720\nhigh.m3u8\n",
            "application/vnd.apple.mpegurl"));
        _app.MapGet("/hls/high.m3u8", () =>
        {
            var lines = new List<string> { "#EXTM3U", "#EXT-X-TARGETDURATION:4", "#EXT-X-MEDIA-SEQUENCE:0" };
            for (var i = 0; i < HlsSegments.Length; i++)
            {
                // Second half is encrypted with the default IV (the segment's sequence number).
                if (i == 3) lines.Add("#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\"");
                lines.Add("#EXTINF:4.0,");
                lines.Add($"seg{i}.ts");
            }
            lines.Add("#EXT-X-ENDLIST");
            return Results.Text(string.Join('\n', lines), "application/vnd.apple.mpegurl");
        });
        _app.MapGet("/hls/key.bin", () => Results.Bytes(HlsKey));
        _app.MapGet("/hls/seg{index:int}.ts", (int index) =>
        {
            var data = HlsSegments[index];
            if (index >= 3)
            {
                using var aes = Aes.Create();
                aes.Key = HlsKey;
                var iv = new byte[16];
                iv[15] = (byte)index;
                data = aes.EncryptCbc(data, iv, PaddingMode.PKCS7);
            }
            return Results.Bytes(data, "video/mp2t");
        });
        await _app.StartAsync();
        BaseUrl = _app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.First();
    }

    public string Url(string path) => BaseUrl + path;

    static (long From, long? To)? ParseRange(string header)
    {
        if (!header.StartsWith("bytes=")) return null;
        var parts = header[6..].Split('-');
        return (long.Parse(parts[0]), parts.Length > 1 && parts[1].Length > 0 ? long.Parse(parts[1]) : null);
    }

    public async Task DisposeAsync()
    {
        if (_app is not null) await _app.DisposeAsync();
    }
}

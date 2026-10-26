using System.Diagnostics;
using System.Security.Cryptography;
using Jiza.Core.Engine;
using Jiza.Core.Model;
using Jiza.Core.Queue;

namespace Jiza.Core.Tests;

public sealed class EngineTests(TestServer server) : IClassFixture<TestServer>, IDisposable
{
    readonly string _root = Directory.CreateTempSubdirectory("jiza-tests-").FullName;

    DownloadManager NewManager()
    {
        var manager = new DownloadManager(Path.Combine(_root, "data"), tools: new ToolLocator(Path.Combine(_root, "no-tools")));
        var settings = manager.Settings;
        settings.DownloadFolder = Path.Combine(_root, "out");
        settings.UseCategoryFolders = false;
        manager.UpdateSettings(settings);
        return manager;
    }

    static async Task<DownloadItem> WaitFor(DownloadItem item, Func<DownloadItem, bool> condition, int seconds = 30)
    {
        var watch = Stopwatch.StartNew();
        while (!condition(item))
        {
            if (watch.Elapsed > TimeSpan.FromSeconds(seconds)) throw new TimeoutException($"{item.State}: {item.Status}");
            await Task.Delay(50);
        }
        return item;
    }

    static Task<DownloadItem> WaitDone(DownloadItem item, int seconds = 30) =>
        WaitFor(item, i => i.State is DownloadState.Completed or DownloadState.Failed, seconds);

    string Sha(byte[] data) => Convert.ToHexString(SHA256.HashData(data));
    string ShaFile(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));

    [Fact]
    public async Task SegmentedDownloadMatchesSourceAndUsesManyConnections()
    {
        using var manager = NewManager();
        var item = manager.Add(new DownloadRequest(server.Url("/file.bin")));
        await WaitDone(item);
        Assert.Equal(DownloadState.Completed, item.State);
        Assert.Equal(Sha(server.File), ShaFile(item.LocalPath!));
        Assert.True(item.Segments.Count >= 8, $"expected parallel segments, got {item.Segments.Count}");
        Assert.False(File.Exists(item.LocalPath + ".jdpart"));
    }

    [Fact]
    public async Task SameNameDownloadsDoNotShareData()
    {
        using var manager = NewManager();
        var first = manager.Add(new DownloadRequest(server.Url("/file.bin")));
        var second = manager.Add(new DownloadRequest(server.Url("/file.bin")));
        await WaitDone(first);
        await WaitDone(second);
        Assert.True(first.State == DownloadState.Completed && second.State == DownloadState.Completed,
            $"first: {first.State} {first.Status} | second: {second.State} {second.Status}");
        Assert.NotEqual(first.LocalPath, second.LocalPath);
        Assert.Equal(Sha(server.File), ShaFile(first.LocalPath!));
        Assert.Equal(Sha(server.File), ShaFile(second.LocalPath!));
    }

    [Fact]
    public async Task ContentDispositionNameIsUsed()
    {
        using var manager = NewManager();
        var item = await WaitDone(manager.Add(new DownloadRequest(server.Url("/download"))));
        Assert.Equal("report final.pdf", item.FileName);
    }

    [Fact]
    public async Task ServerWithoutRangesFallsBackToSingleStream()
    {
        using var manager = NewManager();
        var item = await WaitDone(manager.Add(new DownloadRequest(server.Url("/norange.bin"))));
        Assert.Equal(DownloadState.Completed, item.State);
        Assert.False(item.Resumable);
        Assert.Equal(Sha(server.File), ShaFile(item.LocalPath!));
    }

    [Fact]
    public async Task ServerThatLimitsConnectionsStillCompletes()
    {
        using var manager = NewManager();
        var item = await WaitDone(manager.Add(new DownloadRequest(server.Url("/limited.bin"))), 60);
        Assert.Equal(DownloadState.Completed, item.State);
        Assert.Equal(Sha(server.File), ShaFile(item.LocalPath!));
    }

    [Fact]
    public async Task MissingFileFailsWithExplanation()
    {
        using var manager = NewManager();
        var item = await WaitDone(manager.Add(new DownloadRequest(server.Url("/missing"))));
        Assert.Equal(DownloadState.Failed, item.State);
        Assert.Contains("404", item.Status);
    }

    [Fact]
    public async Task PausedDownloadResumesAfterRestartWithoutRedownloading()
    {
        server.SlowChunk = 16 * 1024;
        Guid id;
        long before;
        using (var manager = NewManager())
        {
            var item = manager.Add(new DownloadRequest(server.Url("/slow.bin")));
            id = item.Id;
            await WaitFor(item, i => i.DownloadedBytes > 2 * 1024 * 1024);
            manager.Pause(item);
            await WaitFor(item, i => i.State == DownloadState.Paused);
            before = item.DownloadedBytes;
            Assert.True(item.Resumable);
        }
        // A fresh manager simulates quitting and relaunching the app.
        server.SlowChunk = 512 * 1024;
        while (server.Requests.TryDequeue(out _)) { }
        using (var manager = NewManager())
        {
            manager.Load();
            var item = manager.Snapshot().Single(i => i.Id == id);
            Assert.Equal(DownloadState.Paused, item.State);
            Assert.True(item.DownloadedBytes >= before - 1);
            manager.Start(item);
            await WaitDone(item, 60);
            Assert.Equal(DownloadState.Completed, item.State);
            Assert.Equal(Sha(server.File), ShaFile(item.LocalPath!));
            // No connection after the restart asked for byte 0 again.
            Assert.DoesNotContain(server.Requests, r => r.Path == "/slow.bin" && r.From == 0);
        }
    }

    [Fact]
    public async Task HlsPicksBestVariantDecryptsAndJoins()
    {
        using var manager = NewManager();
        var item = await WaitDone(manager.Add(new DownloadRequest(server.Url("/hls/master.m3u8"))));
        Assert.Equal(DownloadState.Completed, item.State);
        Assert.Equal(DownloadKind.Hls, item.Kind);
        Assert.EndsWith(".ts", item.LocalPath);
        Assert.Equal(server.HlsSegments.SelectMany(s => s).ToArray(), File.ReadAllBytes(item.LocalPath!));
    }

    [Fact]
    public async Task SpeedLimiterHoldsRate()
    {
        var limiter = new SpeedLimiter(4 * 1024 * 1024);
        var watch = Stopwatch.StartNew();
        for (var i = 0; i < 32; i++) await limiter.WaitAsync(64 * 1024, CancellationToken.None);
        // 2 MB at 4 MB/s: at least ~0.4 s after the initial burst allowance.
        Assert.InRange(watch.Elapsed.TotalSeconds, 0.3, 2.0);
    }

    [Fact]
    public async Task AnalyzerReportsSizeAndResumability()
    {
        using var manager = NewManager();
        var ctx = new DownloadContext { Http = manager.Http, Settings = manager.Settings, Tools = manager.Tools };
        var info = await LinkAnalyzer.AnalyzeAsync(server.Url("/file.bin"), new Dictionary<string, string>(), ctx, CancellationToken.None);
        Assert.Equal(DownloadKind.Http, info.Kind);
        Assert.Equal(server.File.Length, info.Size);
        Assert.True(info.Resumable);
        Assert.Equal("file.bin", info.FileName);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch (IOException) { }
    }
}

using Jiza.Core.Model;
using Jiza.Core.Queue;
using MonoTorrent;
using MonoTorrent.Client;

namespace Jiza.Core.Engine;

/// Magnet links and .torrent files (by URL or local path) through MonoTorrent, with DHT, PEX and fast resume.
/// Ported behaviour from Jiza's TorrentModel: import a .torrent or magnet, pause per torrent, remember sources.
public sealed class TorrentDownloader(string? cacheFolder = null) : IDownloader, IRemovable, IDisposable
{
    const int MaxTorrentFileBytes = 20 * 1024 * 1024;
    readonly SemaphoreSlim _gate = new(1, 1);
    readonly Dictionary<Guid, TorrentManager> _managers = [];
    readonly string _cache = cacheFolder ?? Path.Combine(Store.DefaultDataFolder, "torrents");
    ClientEngine? _engine;

    public DownloadKind Kind => DownloadKind.Torrent;

    ClientEngine Engine()
    {
        if (_engine is not null) return _engine;
        Directory.CreateDirectory(_cache);
        var settings = new EngineSettingsBuilder
        {
            CacheDirectory = _cache,
            AllowPortForwarding = true,
            AutoSaveLoadFastResume = true,
            AutoSaveLoadMagnetLinkMetadata = true,
            AutoSaveLoadDhtCache = true,
            MaximumConnections = 400,
            MaximumHalfOpenConnections = 24,
        }.ToSettings();
        return _engine = new ClientEngine(settings);
    }

    async Task<TorrentManager> ManagerAsync(DownloadItem item, DownloadContext ctx, CancellationToken ct)
    {
        await _gate.WaitAsync(ct);
        try
        {
            if (_managers.TryGetValue(item.Id, out var existing)) return existing;
            var engine = Engine();
            Directory.CreateDirectory(item.Folder);
            var settings = new TorrentSettingsBuilder { MaximumConnections = 120, AllowDht = true, AllowPeerExchange = true, CreateContainingDirectory = true }.ToSettings();
            TorrentManager manager;
            if (item.Url.StartsWith("magnet:", StringComparison.OrdinalIgnoreCase))
            {
                var magnet = MagnetLink.Parse(item.Url);
                manager = engine.Torrents.FirstOrDefault(t => t.InfoHashes == magnet.InfoHashes)
                    ?? await engine.AddAsync(magnet, item.Folder, settings);
            }
            else
            {
                var torrent = await Torrent.LoadAsync(await TorrentBytesAsync(item, ctx, ct));
                manager = engine.Torrents.FirstOrDefault(t => t.InfoHashes == torrent.InfoHashes)
                    ?? await engine.AddAsync(torrent, item.Folder, settings);
            }
            _managers[item.Id] = manager;
            return manager;
        }
        finally { _gate.Release(); }
    }

    static async Task<Memory<byte>> TorrentBytesAsync(DownloadItem item, DownloadContext ctx, CancellationToken ct)
    {
        var uri = new Uri(item.Url);
        byte[] bytes;
        if (uri.IsFile) bytes = await File.ReadAllBytesAsync(uri.LocalPath, ct);
        else
        {
            using var request = ctx.Request(item, uri);
            using var response = await ctx.Http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
            if (!response.IsSuccessStatusCode) throw DownloadException.ForStatus((int)response.StatusCode);
            if (response.Content.Headers.ContentLength > MaxTorrentFileBytes) throw new DownloadException("This .torrent file is larger than 20 MB.");
            bytes = await response.Content.ReadAsByteArrayAsync(ct);
        }
        if (bytes.Length is 0 or > MaxTorrentFileBytes) throw new DownloadException("Choose a .torrent file smaller than 20 MB.");
        return bytes;
    }

    public async Task RunAsync(DownloadItem item, DownloadContext ctx, CancellationToken ct)
    {
        item.State = DownloadState.Connecting;
        item.Status = "Starting torrent";
        TorrentManager manager;
        try { manager = await ManagerAsync(item, ctx, ct); }
        catch (Exception e) when (e is not OperationCanceledException and not DownloadException)
        { throw new DownloadException("This is not a valid torrent: " + e.Message, inner: e); }

        var limit = new[] { item.SpeedLimit, ctx.Settings.GlobalSpeedLimit }.Where(l => l > 0).DefaultIfEmpty(0).Min();
        await manager.UpdateSettingsAsync(new TorrentSettingsBuilder(manager.Settings) { MaximumDownloadRate = (int)Math.Min(int.MaxValue, limit) }.ToSettings());
        if (manager.State is TorrentState.Stopped or TorrentState.Paused or TorrentState.Error) await manager.StartAsync();
        item.Resumable = true;

        try
        {
            while (true)
            {
                ct.ThrowIfCancellationRequested();
                var size = manager.Torrent?.Size ?? -1;
                if (manager.Torrent is { } torrent && (string.IsNullOrEmpty(item.FileName) || item.FileName == "Torrent"))
                    item.FileName = FileNaming.Safe(torrent.Name);
                item.TotalBytes = size;
                item.ProgressOverride = manager.Progress / 100.0;
                if (size > 0) item.DownloadedBytes = (long)(size * manager.Progress / 100.0);
                item.ActiveConnections = manager.OpenConnections;
                switch (manager.State)
                {
                    case TorrentState.Metadata:
                        item.State = DownloadState.Connecting;
                        item.Status = "Getting torrent info from peers";
                        break;
                    case TorrentState.Hashing or TorrentState.FetchingHashes:
                        item.State = DownloadState.Connecting;
                        item.Status = "Checking existing data";
                        break;
                    case TorrentState.Error:
                        throw new DownloadException("Torrent error: " + (manager.Error?.Exception?.Message ?? "unknown"), retryable: true);
                    case TorrentState.Seeding when ctx.Settings.SeedRatio > 0 && size > 0:
                        var ratio = manager.Monitor.DataBytesSent / (double)size;
                        if (ratio >= ctx.Settings.SeedRatio) return;
                        item.State = DownloadState.Downloading;
                        item.Status = $"Seeding to {manager.UploadingTo} peers (ratio {ratio:0.00} of {ctx.Settings.SeedRatio:0.##})";
                        break;
                    case TorrentState.Seeding:
                        return;
                    default:
                        item.State = DownloadState.Downloading;
                        item.Status = manager.OpenConnections > 0 ? $"Downloading from {manager.OpenConnections} peers" : "Looking for peers";
                        break;
                }
                await Task.Delay(500, ct);
            }
        }
        finally
        {
            item.ActiveConnections = 0;
            // ct may already be cancelled (pause); stopping must still run.
            try { await manager.StopAsync(TimeSpan.FromSeconds(10)); } catch (Exception) { }
            if (manager.Complete) item.LocalPath = OutputPath(manager);
        }
    }

    static string OutputPath(TorrentManager manager) =>
        manager.Files.Count == 1 ? manager.Files[0].FullPath : manager.ContainingDirectory;

    public async Task RemoveAsync(DownloadItem item, bool deleteFiles)
    {
        await _gate.WaitAsync();
        try
        {
            if (!_managers.Remove(item.Id, out var manager) || _engine is null) return;
            try { await manager.StopAsync(TimeSpan.FromSeconds(5)); } catch (Exception) { }
            await _engine.RemoveAsync(manager, deleteFiles ? RemoveMode.CacheDataAndDownloadedData : RemoveMode.CacheDataOnly);
        }
        finally { _gate.Release(); }
    }

    public void Dispose()
    {
        if (_engine is null) return;
        try { _engine.StopAllAsync(TimeSpan.FromSeconds(5)).Wait(TimeSpan.FromSeconds(8)); } catch (Exception) { }
        _engine.Dispose();
        _engine = null;
    }
}

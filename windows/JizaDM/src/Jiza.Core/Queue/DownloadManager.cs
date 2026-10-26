using System.Collections.ObjectModel;
using Jiza.Core.Engine;
using Jiza.Core.Model;

namespace Jiza.Core.Queue;

/// What the add dialog, clipboard monitor or browser extension hands over.
public sealed record DownloadRequest(string Url)
{
    public DownloadKind? Kind { get; init; }
    public string? FileName { get; init; }
    public string? Folder { get; init; }
    public string? Referrer { get; init; }
    public string? Cookies { get; init; }
    public string? UserAgent { get; init; }
    public string? MediaFormat { get; init; }
    public long TotalBytes { get; init; } = -1;
    public Dictionary<string, string>? Headers { get; init; }
}

public sealed class DownloadManager : IDisposable
{
    readonly object _gate = new();
    readonly List<DownloadItem> _items = [];
    readonly Dictionary<Guid, (CancellationTokenSource Cts, Task Task)> _running = [];
    readonly Dictionary<Guid, (long Bytes, DateTime At)> _samples = [];
    readonly Dictionary<DownloadKind, IDownloader> _downloaders;
    readonly Store _store;
    readonly Timer _sampler;
    DateTime _lastSave = DateTime.MinValue;
    bool _dirty;

    public ObservableCollection<DownloadItem> Items { get; } = [];
    public DownloadSettings Settings { get; private set; }
    public HttpClient Http { get; private set; }
    public SpeedLimiter GlobalLimiter { get; } = new();
    public ToolLocator Tools { get; }
    /// Marshals collection changes to the UI thread; the app replaces this with Dispatcher.Invoke.
    public Action<Action> Dispatch { get; set; } = action => action();

    public event EventHandler<DownloadItem>? Completed;
    public event EventHandler<DownloadItem>? Failed;
    /// Raised when the last scheduled item finishes (drives "when done" actions).
    public event EventHandler? ScheduleDrained;

    public DownloadManager(string? dataFolder = null, IEnumerable<IDownloader>? downloaders = null, ToolLocator? tools = null)
    {
        _store = new Store(dataFolder ?? Store.DefaultDataFolder);
        Settings = _store.LoadSettings();
        Http = HttpFactory.Create(Settings);
        GlobalLimiter.BytesPerSecond = Settings.GlobalSpeedLimit;
        Tools = tools ?? new ToolLocator(Path.Combine(_store.Folder, "tools"));
        _downloaders = (downloaders ?? DefaultDownloaders()).ToDictionary(d => d.Kind);
        _sampler = new Timer(_ => Tick(), null, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(1));
    }

    public static IEnumerable<IDownloader> DefaultDownloaders() =>
        [new HttpDownloader(), new FtpDownloader(), new HlsDownloader(), new MediaDownloader(), new TorrentDownloader()];

    public string DataFolder => _store.Folder;

    public void Load()
    {
        var loaded = _store.LoadDownloads();
        foreach (var item in loaded)
        {
            if (item.IsActive || item.State == DownloadState.Queued)
            {
                item.State = DownloadState.Paused;
                item.Status = "Interrupted. Resume to continue.";
            }
        }
        lock (_gate) _items.AddRange(loaded);
        Dispatch(() => { foreach (var item in loaded) Items.Add(item); });
    }

    public IReadOnlyList<DownloadItem> Snapshot() { lock (_gate) return _items.ToList(); }

    public DownloadItem Add(DownloadRequest request, bool start = true, bool schedule = false)
    {
        var kind = request.Kind ?? LinkAnalyzer.GuessKind(request.Url);
        var name = request.FileName is { Length: > 0 } n ? FileNaming.Safe(n) : "";
        var category = Categories.For(name.Length > 0 ? name : SafeUrlName(request.Url), kind);
        var item = new DownloadItem
        {
            Url = request.Url.Trim(),
            Kind = kind,
            FileName = name,
            Category = category,
            Folder = request.Folder ?? Settings.FolderFor(category),
            Connections = Settings.Connections,
            MediaFormat = request.MediaFormat,
            TotalBytes = request.TotalBytes,
            InSchedule = schedule,
            State = DownloadState.Paused,
            Status = schedule ? "Waiting for scheduler" : "Not started",
        };
        if (request.Headers is not null) foreach (var (k, v) in request.Headers) item.Headers[k] = v;
        if (!string.IsNullOrEmpty(request.Referrer)) item.Headers["Referer"] = request.Referrer;
        if (!string.IsNullOrEmpty(request.Cookies)) item.Headers["Cookie"] = request.Cookies;
        if (!string.IsNullOrEmpty(request.UserAgent)) item.Headers["User-Agent"] = request.UserAgent;

        lock (_gate) _items.Insert(0, item);
        Dispatch(() => Items.Insert(0, item));
        MarkDirty();
        if (start) Start(item);
        return item;
    }

    public void Start(DownloadItem item)
    {
        lock (_gate)
        {
            if (_running.ContainsKey(item.Id) || item.State == DownloadState.Completed) return;
            item.State = DownloadState.Queued;
            item.Status = "Waiting in queue";
        }
        Pump();
    }

    public void Pause(DownloadItem item)
    {
        lock (_gate)
        {
            if (_running.TryGetValue(item.Id, out var run)) { run.Cts.Cancel(); return; }
            if (item.State == DownloadState.Queued) { item.State = DownloadState.Paused; item.Status = "Paused"; }
        }
    }

    public void StartAll() { foreach (var item in Snapshot().Where(i => i.CanStart).Reverse()) Start(item); }
    public void PauseAll() { foreach (var item in Snapshot()) Pause(item); }

    /// Starts again from zero, discarding partial data.
    public async Task RestartAsync(DownloadItem item)
    {
        await StopAndWaitAsync(item);
        HttpDownloader.Reset(item);
        item.LocalPath = null;
        item.CompletedAt = null;
        item.ProgressOverride = null;
        item.State = DownloadState.Paused;
        Start(item);
    }

    /// Forgetting a download keeps a finished file unless deleteFile is set (as in Jiza); partial data is removed.
    public async Task RemoveAsync(DownloadItem item, bool deleteFile)
    {
        await StopAndWaitAsync(item);
        lock (_gate) _items.Remove(item);
        Dispatch(() => Items.Remove(item));
        if (item.PartPath is { } part) HttpDownloader.TryDelete(part);
        if (_downloaders.TryGetValue(item.Kind, out var downloader) && downloader is IRemovable removable)
            await removable.RemoveAsync(item, deleteFile);
        if (deleteFile && item.LocalPath is { } path)
        {
            try
            {
                if (File.Exists(path)) File.Delete(path);
                else if (Directory.Exists(path)) Directory.Delete(path, recursive: true);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
        MarkDirty();
        SaveNow();
    }

    async Task StopAndWaitAsync(DownloadItem item)
    {
        Task? task = null;
        lock (_gate)
        {
            if (_running.TryGetValue(item.Id, out var run)) { run.Cts.Cancel(); task = run.Task; }
            else if (item.State == DownloadState.Queued) item.State = DownloadState.Paused;
        }
        if (task is not null) try { await task; } catch { }
    }

    public void UpdateSettings(DownloadSettings settings)
    {
        var proxyChanged = settings.Proxy != Settings.Proxy;
        Settings = settings;
        GlobalLimiter.BytesPerSecond = settings.GlobalSpeedLimit;
        if (proxyChanged) Http = HttpFactory.Create(settings);
        _store.SaveSettings(settings);
        Pump();
    }

    public void Pump()
    {
        lock (_gate)
        {
            // Queued items run in the order they were added (the list is newest first).
            foreach (var item in _items.Where(i => i.State == DownloadState.Queued).Reverse().ToList())
            {
                if (_running.Count >= Math.Max(1, Settings.MaxConcurrent)) break;
                Run(item);
            }
        }
    }

    void Run(DownloadItem item)
    {
        if (!_downloaders.TryGetValue(item.Kind, out var downloader))
        {
            item.State = DownloadState.Failed;
            item.Status = $"No downloader for {item.Kind} links.";
            return;
        }
        var cts = new CancellationTokenSource();
        var context = new DownloadContext
        {
            Http = Http,
            Settings = Settings,
            GlobalLimiter = GlobalLimiter,
            Tools = Tools,
            Checkpoint = _ => MarkDirty(),
        };
        item.State = DownloadState.Connecting;
        item.Status = "Connecting";
        var task = Task.Run(async () =>
        {
            try
            {
                await downloader.RunAsync(item, context, cts.Token);
                item.State = DownloadState.Completed;
                item.Status = "Complete";
                item.CompletedAt = DateTime.Now;
                item.ProgressOverride = null;
                Completed?.Invoke(this, item);
            }
            catch (OperationCanceledException) when (cts.IsCancellationRequested)
            {
                item.State = DownloadState.Paused;
                item.Status = item.Resumable || item.Kind != DownloadKind.Http ? "Paused" : "Paused (this server can't resume; it will restart)";
            }
            catch (DownloadException e)
            {
                Fail(item, e.Message);
            }
            catch (OperationCanceledException)
            {
                // Not a pause: a connect or read timeout inside the HTTP stack.
                Fail(item, "Could not reach the server: the connection timed out. Check the address or your network, then retry.");
            }
            catch (Exception e)
            {
                Fail(item, "Failed: " + e.Message);
            }
            finally
            {
                item.BytesPerSecond = 0;
                item.ActiveConnections = 0;
                lock (_gate) { _running.Remove(item.Id); _samples.Remove(item.Id); }
                cts.Dispose();
                MarkDirty();
                SaveNow();
                Pump();
                CheckScheduleDrained(item);
            }
        });
        _running[item.Id] = (cts, task);
    }

    void Fail(DownloadItem item, string message)
    {
        item.State = DownloadState.Failed;
        item.Status = message;
        Failed?.Invoke(this, item);
    }

    void CheckScheduleDrained(DownloadItem finished)
    {
        if (!finished.InSchedule) return;
        bool drained;
        lock (_gate) drained = _items.Where(i => i.InSchedule).All(i => i.State is DownloadState.Completed or DownloadState.Failed);
        if (drained) ScheduleDrained?.Invoke(this, EventArgs.Empty);
    }

    public bool IsRunning(DownloadItem item) { lock (_gate) return _running.ContainsKey(item.Id); }
    public int RunningCount { get { lock (_gate) return _running.Count; } }
    public double TotalSpeed => Snapshot().Where(i => i.IsActive).Sum(i => i.BytesPerSecond);

    void Tick()
    {
        var now = DateTime.UtcNow;
        List<DownloadItem> active;
        lock (_gate) active = _items.Where(i => _running.ContainsKey(i.Id)).ToList();
        foreach (var item in active)
        {
            var bytes = item.DownloadedBytes;
            lock (_gate)
            {
                if (_samples.TryGetValue(item.Id, out var last))
                {
                    var seconds = (now - last.At).TotalSeconds;
                    var instant = seconds > 0 ? Math.Max(0, bytes - last.Bytes) / seconds : 0;
                    // Smooth so the speed column doesn't jitter.
                    item.BytesPerSecond = item.BytesPerSecond <= 0 ? instant : item.BytesPerSecond * 0.6 + instant * 0.4;
                }
                _samples[item.Id] = (bytes, now);
            }
        }
        if (_dirty && now - _lastSave > TimeSpan.FromSeconds(3)) SaveNow();
    }

    void MarkDirty() => _dirty = true;

    public void SaveNow()
    {
        _dirty = false;
        _lastSave = DateTime.UtcNow;
        try { _store.SaveDownloads(Snapshot()); }
        catch (IOException) { _dirty = true; }
    }

    static string SafeUrlName(string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) ? Path.GetFileName(uri.AbsolutePath) : "";

    public void Dispose()
    {
        _sampler.Dispose();
        List<Task> tasks;
        lock (_gate)
        {
            foreach (var run in _running.Values) run.Cts.Cancel();
            tasks = _running.Values.Select(r => r.Task).ToList();
        }
        try { Task.WaitAll(tasks.ToArray(), TimeSpan.FromSeconds(5)); } catch (AggregateException) { }
        foreach (var downloader in _downloaders.Values) (downloader as IDisposable)?.Dispose();
        SaveNow();
    }
}

/// Downloaders that hold resources per item (torrent sessions) clean them up on removal.
public interface IRemovable
{
    Task RemoveAsync(DownloadItem item, bool deleteFiles);
}

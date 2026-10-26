using System.IO;
using System.Windows;
using System.Windows.Threading;
using Jiza.Core;
using Jiza.Core.Model;
using Jiza.Core.Queue;

namespace Jiza.App;

public partial class App : Application
{
    public static new App Current => (App)Application.Current;

    public DownloadManager Manager { get; private set; } = null!;
    public Scheduler Scheduler { get; private set; } = null!;
    public bool IsExiting { get; private set; }

    readonly CancellationTokenSource _ipc = new();
    readonly DispatcherTimer _tooltip = new() { Interval = TimeSpan.FromSeconds(1) };
    Tray? _tray;
    ClipboardMonitor? _clipboard;
    MainWindow? _main;
    Mutex? _instance;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Started by Chrome/Edge as the native messaging host: no UI, just relay to the running app.
        if (NativeHost.IsNativeHostLaunch(e.Args))
        {
            Shutdown(await NativeHost.RunAsync());
            return;
        }

        var incoming = e.Args.Select(Integration.FromArgument).OfType<IncomingRequest>().ToList();
        _instance = new Mutex(true, @"Local\" + Ipc.PipeName, out var first);
        if (!first)
        {
            if (incoming.Count == 0 && !e.Args.Contains("--tray")) incoming.Add(new IncomingRequest { Type = "show" });
            foreach (var request in incoming) await Ipc.SendAsync(request, TimeSpan.FromSeconds(3));
            Shutdown();
            return;
        }

        DispatcherUnhandledException += (_, args) =>
        {
            Log(args.Exception);
            MessageBox.Show(args.Exception.Message, "Jiza Download Manager", MessageBoxButton.OK, MessageBoxImage.Warning);
            args.Handled = true;
        };

        Manager = new DownloadManager { Dispatch = action => Dispatcher.Invoke(action) };
        Theme.Apply(Manager.Settings.Theme);
        if (Manager.Settings.AcceptedLicense != LicenseWindow.CurrentVersion)
        {
            if (new LicenseWindow("license.txt", askToAccept: true).ShowDialog() != true)
            {
                Manager.Dispose();
                Shutdown();
                return;
            }
            var accepted = Manager.Settings;
            accepted.AcceptedLicense = LicenseWindow.CurrentVersion;
            Manager.UpdateSettings(accepted);
        }
        Manager.Load();
        Manager.Completed += (_, item) => Dispatcher.BeginInvoke(() => OnCompleted(item));
        Manager.Failed += (_, item) => Dispatcher.BeginInvoke(() => _tray?.Balloon("Download failed", $"{item.FileName}\n{item.Status}"));
        Scheduler = new Scheduler(Manager);
        Scheduler.Notify += message => _tray?.Balloon("Jiza scheduler", message);

        _tray = new Tray(this);
        _clipboard = new ClipboardMonitor { Enabled = Manager.Settings.MonitorClipboard };
        _clipboard.LinkCopied += url => ShowAddDialog(new IncomingRequest { Url = url });
        try { Integration.Register(); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { Log(ex); }

        _ = Ipc.ServeAsync(request =>
        {
            if (request.Type == "download" && !Manager.Settings.CaptureBrowserDownloads) return false;
            Dispatcher.BeginInvoke(() => Handle(request));
            return true;
        }, _ipc.Token);
        _tooltip.Tick += (_, _) => _tray?.UpdateTooltip(Manager.TotalSpeed, Manager.RunningCount);
        _tooltip.Start();

        _main = new MainWindow(Manager);
        if (!e.Args.Contains("--tray")) _main.Show();
        foreach (var request in incoming) Handle(request);
    }

    public void Handle(IncomingRequest request)
    {
        Trace($"incoming {request.Type}: {request.Url}");
        switch (request.Type)
        {
            case "ping":
                return;
            case "show":
                ShowMain();
                return;
            case "batch":
                var links = (request.Items ?? []).Where(i => !string.IsNullOrWhiteSpace(i.Url)).ToList();
                foreach (var link in links) Manager.Add(link.ToDownloadRequest() with { Referrer = link.Referrer ?? request.PageUrl, Cookies = link.Cookies ?? request.Cookies }, start: false);
                ShowMain();
                _tray?.Balloon("Added to Jiza", $"{links.Count} link(s) added. Select them and press Resume to start.");
                return;
            default:
                if (string.IsNullOrWhiteSpace(request.Url)) return;
                if (request.Type == "download" && Manager.Settings.StartWithoutAsking)
                {
                    var item = Manager.Add(request.ToDownloadRequest());
                    _tray?.Balloon("Downloading", item.FileName.Length > 0 ? item.FileName : request.Url);
                }
                else ShowAddDialog(request);
                return;
        }
    }

    public void ShowMain()
    {
        if (_main is null) return;
        _main.Show();
        if (_main.WindowState == WindowState.Minimized) _main.WindowState = WindowState.Normal;
        _main.Activate();
    }

    public void ShowAddDialog(IncomingRequest? request)
    {
        var window = new AddUrlWindow(Manager, request);
        window.Show();
        window.Activate();
    }

    void OnCompleted(DownloadItem item)
    {
        if (!Manager.Settings.ShowCompleteDialog) return;
        _tray?.Balloon("Download complete", item.FileName + "\nClick to show it in its folder.", () =>
        {
            if (item.LocalPath is { } path) Shell.ShowInFolder(path);
        });
    }

    public void SetSpeedLimit(long bytesPerSecond)
    {
        var settings = Manager.Settings;
        settings.GlobalSpeedLimit = bytesPerSecond;
        Manager.UpdateSettings(settings);
    }

    public void SetTheme(string theme)
    {
        var settings = Manager.Settings;
        settings.Theme = theme;
        Manager.UpdateSettings(settings);
        Theme.Apply(theme);
    }

    public void SetClipboardMonitor(bool enabled)
    {
        var settings = Manager.Settings;
        settings.MonitorClipboard = enabled;
        Manager.UpdateSettings(settings);
        if (_clipboard is not null) _clipboard.Enabled = enabled;
    }

    public void ApplySettings(DownloadSettings settings)
    {
        Manager.UpdateSettings(settings);
        Theme.Apply(settings.Theme);
        if (_clipboard is not null) _clipboard.Enabled = settings.MonitorClipboard;
        try { Integration.SetStartWithWindows(settings.StartWithWindows); }
        catch (UnauthorizedAccessException ex) { Log(ex); }
    }

    public void IgnoreClipboard(string text)
    {
        if (_clipboard is not null) _clipboard.Ignore = text;
    }

    public void ExitApp()
    {
        if (IsExiting) return;
        var running = Manager.RunningCount;
        if (running > 0 && MessageBox.Show($"{running} download(s) are running. They'll pause and can resume next time. Exit Jiza?", "Exit Jiza",
                MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        IsExiting = true;
        _ipc.Cancel();
        _tooltip.Stop();
        Manager.Dispose();
        _clipboard?.Dispose();
        _tray?.Dispose();
        _main?.Close();
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        _instance?.Dispose();
        base.OnExit(e);
    }

    /// Browser-integration breadcrumbs (no cookies or headers are written).
    public static void Trace(string message)
    {
        try
        {
            Directory.CreateDirectory(Store.DefaultDataFolder);
            File.AppendAllText(Path.Combine(Store.DefaultDataFolder, "browser.log"), $"{DateTime.Now:O} [{Environment.ProcessId}] {message}\n");
        }
        catch (IOException) { }
    }

    public static void Log(Exception e)
    {
        try
        {
            Directory.CreateDirectory(Store.DefaultDataFolder);
            File.AppendAllText(Path.Combine(Store.DefaultDataFolder, "jiza.log"), $"{DateTime.Now:O} {e}\n");
        }
        catch (IOException) { }
    }
}

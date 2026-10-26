using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Windows;
using Jiza.Core.Model;
using Jiza.Core.Queue;
using Microsoft.Win32;

namespace Jiza.App;

public partial class SettingsWindow : Window
{
    readonly DownloadManager _manager;
    readonly DownloadSettings _settings;
    /// Same order as Theme.Choices.
    static readonly string[] ThemeLabels = ["Follow Windows", "Light", "Dark"];

    public SettingsWindow(DownloadManager manager)
    {
        _manager = manager;
        // Edit a copy so Cancel leaves the live settings untouched.
        _settings = JsonSerializer.Deserialize<DownloadSettings>(JsonSerializer.Serialize(manager.Settings))!;
        InitializeComponent();

        FolderBox.Text = _settings.DownloadFolder;
        ThemeBox.ItemsSource = ThemeLabels;
        ThemeBox.SelectedIndex = Math.Max(0, Array.IndexOf(Theme.Choices, _settings.Theme));
        CategoryFolders.IsChecked = _settings.UseCategoryFolders;
        ClipboardBox.IsChecked = _settings.MonitorClipboard;
        NoAsk.IsChecked = _settings.StartWithoutAsking;
        CompleteNotice.IsChecked = _settings.ShowCompleteDialog;
        Startup.IsChecked = _settings.StartWithWindows;
        ConnectionsSlider.Value = _settings.Connections;
        ConcurrentSlider.Value = _settings.MaxConcurrent;
        LimitBox.Text = (_settings.GlobalSpeedLimit / 1024).ToString(CultureInfo.InvariantCulture);
        ProxyBox.Text = _settings.Proxy ?? "";
        Capture.IsChecked = _settings.CaptureBrowserDownloads;
        SeedBox.Text = _settings.SeedRatio.ToString(CultureInfo.InvariantCulture);
        ExtensionPath.Text = Integration.ExtensionFolder;
        DataPath.Text = manager.DataFolder;
        VersionText.Text = "Version " + typeof(SettingsWindow).Assembly.GetName().Version?.ToString(3);
        RefreshStatus();
    }

    void RefreshStatus()
    {
        var registered = Integration.IsRegistered();
        BrowserStatus.Text = registered
            ? "Connected: the browser extension can reach Jiza."
            : "Not connected yet. Click Repair connection, then add the extension.";
        BrowserStatus.Foreground = (System.Windows.Media.Brush)FindResource(registered ? "JizaSuccess" : "JizaWarning");
        YtDlpStatus.Text = _manager.Tools.YtDlp ?? "Not installed. It installs itself the first time you download a video.";
        YtDlpButton.Content = _manager.Tools.YtDlp is null ? "Install" : "Update";
        FfmpegStatus.Text = _manager.Tools.Ffmpeg ?? "Not installed (about 100 MB download).";
        FfmpegButton.Content = _manager.Tools.Ffmpeg is null ? "Install" : "Reinstall";
    }

    void OnConnectionsChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (ConnectionsText is not null) ConnectionsText.Text = ((int)e.NewValue).ToString(CultureInfo.CurrentCulture);
    }

    void OnConcurrentChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (ConcurrentText is not null) ConcurrentText.Text = ((int)e.NewValue).ToString(CultureInfo.CurrentCulture);
    }

    void OnViewLicense(object sender, RoutedEventArgs e) => new LicenseWindow("license.txt", askToAccept: false) { Owner = this }.ShowDialog();
    void OnViewNotices(object sender, RoutedEventArgs e) => new LicenseWindow("notices.txt", askToAccept: false) { Owner = this }.ShowDialog();

    void OnBrowse(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "Choose the download folder" };
        if (Directory.Exists(FolderBox.Text)) dialog.InitialDirectory = FolderBox.Text;
        if (dialog.ShowDialog(this) == true) FolderBox.Text = dialog.FolderName;
    }

    void OnOpenExtension(object sender, RoutedEventArgs e)
    {
        Integration.UnpackExtension();
        Shell.Open(Integration.ExtensionFolder);
    }

    void OnCopyExtension(object sender, RoutedEventArgs e)
    {
        App.Current.IgnoreClipboard(Integration.ExtensionFolder);
        Clipboard.SetText(Integration.ExtensionFolder);
    }

    void OnRepair(object sender, RoutedEventArgs e)
    {
        try { Integration.Register(); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { MessageBox.Show(this, ex.Message, "Repair connection"); }
        RefreshStatus();
    }

    async void OnInstallYtDlp(object sender, RoutedEventArgs e) =>
        await InstallAsync(p => _manager.Tools.InstallYtDlpAsync(_manager.Http, p, CancellationToken.None));

    async void OnInstallFfmpeg(object sender, RoutedEventArgs e) =>
        await InstallAsync(p => _manager.Tools.InstallFfmpegAsync(_manager.Http, p, CancellationToken.None));

    async Task InstallAsync(Func<IProgress<double>, Task<string>> install)
    {
        YtDlpButton.IsEnabled = FfmpegButton.IsEnabled = false;
        ToolProgress.Visibility = Visibility.Visible;
        ToolProgress.Value = 0;
        ToolError.Text = "";
        try { await install(new Progress<double>(v => ToolProgress.Value = v)); }
        catch (Exception ex) when (ex is System.Net.Http.HttpRequestException or IOException or InvalidDataException or UnauthorizedAccessException)
        { ToolError.Text = "Install failed: " + ex.Message; }
        finally
        {
            ToolProgress.Visibility = Visibility.Collapsed;
            YtDlpButton.IsEnabled = FfmpegButton.IsEnabled = true;
            RefreshStatus();
        }
    }

    void OnSave(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(FolderBox.Text)) { MessageBox.Show(this, "Choose a download folder.", "Options"); return; }
        if (ProxyBox.Text.Trim() is { Length: > 0 } proxy && !Uri.TryCreate(proxy, UriKind.Absolute, out _))
        { MessageBox.Show(this, "Enter the proxy as a full address, for example http://127.0.0.1:8080.", "Options"); return; }
        _settings.DownloadFolder = FolderBox.Text.Trim();
        _settings.Theme = Theme.Choices[Math.Max(0, ThemeBox.SelectedIndex)];
        _settings.UseCategoryFolders = CategoryFolders.IsChecked == true;
        _settings.MonitorClipboard = ClipboardBox.IsChecked == true;
        _settings.StartWithoutAsking = NoAsk.IsChecked == true;
        _settings.ShowCompleteDialog = CompleteNotice.IsChecked == true;
        _settings.StartWithWindows = Startup.IsChecked == true;
        _settings.Connections = (int)ConnectionsSlider.Value;
        _settings.MaxConcurrent = (int)ConcurrentSlider.Value;
        _settings.GlobalSpeedLimit = long.TryParse(LimitBox.Text.Trim(), out var kb) && kb > 0 ? kb * 1024 : 0;
        _settings.Proxy = ProxyBox.Text.Trim() is { Length: > 0 } p ? p : null;
        _settings.CaptureBrowserDownloads = Capture.IsChecked == true;
        _settings.SeedRatio = double.TryParse(SeedBox.Text.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var ratio) && ratio > 0 ? ratio : 0;
        App.Current.ApplySettings(_settings);
        DialogResult = true;
    }
}

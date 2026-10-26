using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using Jiza.Core.Engine;
using Jiza.Core.Model;
using Jiza.Core.Queue;
using Microsoft.Win32;

namespace Jiza.App;

/// The "Add download" dialog: analyses any link, then lets the user pick name, folder, quality and timing.
public partial class AddUrlWindow : Window
{
    readonly DownloadManager _manager;
    readonly IncomingRequest? _request;
    readonly DispatcherTimer _debounce = new() { Interval = TimeSpan.FromMilliseconds(600) };
    CancellationTokenSource? _analysis;
    LinkInfo? _info;
    bool _folderEdited, _settingFolder;

    public AddUrlWindow(DownloadManager manager, IncomingRequest? request)
    {
        InitializeComponent();
        _manager = manager;
        _request = request;
        CategoryBox.ItemsSource = Categories.All;
        CategoryBox.SelectedItem = Categories.Other;
        ConnectionsSlider.Value = manager.Settings.Connections;
        ReferrerBox.Text = request?.Referrer ?? request?.PageUrl ?? "";
        CookiesBox.Text = request?.Cookies ?? "";
        if (!string.IsNullOrWhiteSpace(request?.FileName)) NameBox.Text = request.FileName;
        _debounce.Tick += (_, _) => { _debounce.Stop(); _ = AnalyzeAsync(); };
        UrlBox.Text = request?.Url ?? "";
        Loaded += (_, _) =>
        {
            if (UrlBox.Text.Length == 0 && Clipboard.ContainsText() && Uri.TryCreate(Clipboard.GetText().Trim(), UriKind.Absolute, out _))
                UrlBox.Text = Clipboard.GetText().Trim();
            UrlBox.Focus();
            UrlBox.SelectAll();
            // Stay on top only while appearing, so the dialog doesn't cover other apps forever.
            Dispatcher.BeginInvoke(() => Topmost = false, DispatcherPriority.ApplicationIdle);
        };
        Closed += (_, _) => _analysis?.Cancel();
    }

    Dictionary<string, string> Headers()
    {
        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (ReferrerBox.Text.Trim() is { Length: > 0 } referrer) headers["Referer"] = referrer;
        if (CookiesBox.Text.Trim() is { Length: > 0 } cookies) headers["Cookie"] = cookies;
        if (_request?.UserAgent is { Length: > 0 } agent) headers["User-Agent"] = agent;
        return headers;
    }

    void OnUrlChanged(object sender, TextChangedEventArgs e)
    {
        _info = null;
        _debounce.Stop();
        if (Uri.TryCreate(UrlBox.Text.Trim(), UriKind.Absolute, out _)) _debounce.Start();
    }

    void OnAnalyze(object sender, RoutedEventArgs e) => _ = AnalyzeAsync();

    async Task AnalyzeAsync()
    {
        var url = UrlBox.Text.Trim();
        if (!Uri.TryCreate(url, UriKind.Absolute, out _)) { ShowError("Enter a full address, for example https://example.com/file.zip or a magnet: link."); return; }
        _analysis?.Cancel();
        var cts = _analysis = new CancellationTokenSource(TimeSpan.FromSeconds(60));
        ShowError(null);
        Busy.Visibility = Visibility.Visible;
        AnalyzeButton.IsEnabled = false;
        KindText.Text = "Checking...";
        var headers = Headers();
        try
        {
            var context = new DownloadContext { Http = _manager.Http, Settings = _manager.Settings, Tools = _manager.Tools };
            var info = await Task.Run(() => LinkAnalyzer.AnalyzeAsync(url, headers, context, cts.Token), cts.Token);
            if (cts != _analysis) return;
            Show(info);
        }
        catch (OperationCanceledException) when (cts != _analysis) { }
        catch (Exception ex)
        {
            if (cts != _analysis) return;
            _info = null;
            KindText.Text = KindLabel(LinkAnalyzer.GuessKind(url));
            ShowError((ex is OperationCanceledException ? "The server took too long to answer." : ex.Message) + " You can still try to download it.");
        }
        finally
        {
            if (cts == _analysis) { Busy.Visibility = Visibility.Collapsed; AnalyzeButton.IsEnabled = true; }
        }
    }

    void Show(LinkInfo info)
    {
        _info = info;
        KindText.Text = KindLabel(info.Kind);
        SizeText.Text = info.Size > 0 ? Format.Bytes(info.Size) : "";
        ResumeText.Text = info.Kind switch
        {
            DownloadKind.Http => info.Resumable ? $"Resume supported · up to {(int)ConnectionsSlider.Value} connections" : "No resume · single connection",
            DownloadKind.Media => info.Title ?? "Video",
            DownloadKind.Hls => "Stream · parallel segments",
            DownloadKind.Torrent => "BitTorrent · DHT and peer exchange",
            _ => "Resume supported",
        };
        if (string.IsNullOrWhiteSpace(_request?.FileName) || NameBox.Text.Length == 0) NameBox.Text = info.FileName;
        NoteText.Text = info.Note ?? "";
        NoteText.Visibility = info.Note is null ? Visibility.Collapsed : Visibility.Visible;
        QualityBox.ItemsSource = info.Choices;
        QualityBox.SelectedIndex = info.Choices.Count > 0 ? 0 : -1;
        QualityPanel.Visibility = info.Choices.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        CategoryBox.SelectedItem = Categories.For(info.FileName, info.Kind);
    }

    static string KindLabel(DownloadKind kind) => kind switch
    {
        DownloadKind.Http => "File",
        DownloadKind.Ftp => "FTP",
        DownloadKind.Hls => "Stream",
        DownloadKind.Media => "Video",
        DownloadKind.Torrent => "Torrent",
        _ => "Link",
    };

    void OnCategoryChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_folderEdited || CategoryBox.SelectedItem is not string category || FolderBox is null) return;
        _settingFolder = true;
        FolderBox.Text = _manager.Settings.FolderFor(category);
        _settingFolder = false;
    }

    void OnFolderEdited(object sender, TextChangedEventArgs e)
    {
        if (!_settingFolder) _folderEdited = true;
    }

    void OnBrowse(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "Choose where to save" };
        if (System.IO.Directory.Exists(FolderBox.Text)) dialog.InitialDirectory = FolderBox.Text;
        if (dialog.ShowDialog(this) == true) FolderBox.Text = dialog.FolderName;
    }

    void OnConnectionsChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (ConnectionsText is not null) ConnectionsText.Text = ((int)e.NewValue).ToString();
    }

    void OnStart(object sender, RoutedEventArgs e) => Add(start: true);
    void OnLater(object sender, RoutedEventArgs e) => Add(start: false);
    void OnCancel(object sender, RoutedEventArgs e) => Close();

    void Add(bool start)
    {
        var url = UrlBox.Text.Trim();
        if (!Uri.TryCreate(url, UriKind.Absolute, out _)) { ShowError("Enter a full address to download."); return; }
        if (string.IsNullOrWhiteSpace(FolderBox.Text)) { ShowError("Choose a folder."); return; }
        var choice = QualityBox.SelectedItem as MediaChoice;
        var kind = _info?.Kind ?? LinkAnalyzer.GuessKind(url);
        var item = _manager.Add(new DownloadRequest(url)
        {
            Kind = kind,
            // Video sites name the file from the title; a chosen name is kept for other kinds.
            FileName = kind == DownloadKind.Media ? null : NameBox.Text.Trim(),
            Folder = FolderBox.Text.Trim(),
            MediaFormat = choice?.Selector,
            TotalBytes = _info?.Size ?? -1,
            Headers = Headers(),
        }, start: false, schedule: !start);
        item.Connections = (int)ConnectionsSlider.Value;
        if (long.TryParse(LimitBox.Text.Trim(), out var limit) && limit > 0) item.SpeedLimit = limit * 1024;
        if (CategoryBox.SelectedItem is string category) item.Category = category;
        if (start)
        {
            _manager.Start(item);
            DetailsWindow.ShowFor(_manager, item, null);
        }
        Close();
    }

    void ShowError(string? message)
    {
        ErrorText.Text = message ?? "";
        ErrorText.Visibility = message is null ? Visibility.Collapsed : Visibility.Visible;
    }
}

using System.Windows;
using System.Windows.Threading;
using Jiza.Core.Model;
using Jiza.Core.Queue;

namespace Jiza.App;

/// Per-download progress window with the segment map and per-connection list.
public partial class DetailsWindow : Window
{
    static readonly Dictionary<Guid, DetailsWindow> Open = [];
    readonly DownloadManager _manager;
    readonly DownloadItem _item;
    readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(300) };

    public sealed record SegmentRow(int Index, string Range, string Done, string State);

    public static void ShowFor(DownloadManager manager, DownloadItem item, Window? owner)
    {
        if (!Open.TryGetValue(item.Id, out var window))
        {
            window = new DetailsWindow(manager, item);
            if (owner is { IsVisible: true }) window.Owner = owner;
            Open[item.Id] = window;
        }
        window.Show();
        window.Activate();
    }

    DetailsWindow(DownloadManager manager, DownloadItem item)
    {
        _manager = manager;
        _item = item;
        InitializeComponent();
        DataContext = item;
        LimitCheck.IsChecked = item.SpeedLimit > 0;
        if (item.SpeedLimit > 0) LimitBox.Text = (item.SpeedLimit / 1024).ToString();
        _timer.Tick += (_, _) => Refresh();
        _timer.Start();
        Closed += (_, _) => { _timer.Stop(); Open.Remove(item.Id); };
        Refresh();
    }

    void Refresh()
    {
        var segments = _item.SnapshotSegments();
        Segments.Update(segments, _item.TotalBytes, _item.Fraction, _item.State == DownloadState.Completed);
        SegmentList.ItemsSource = segments.Select((s, i) => new SegmentRow(i + 1, $"{Format.Bytes(s.Start)} – {Format.Bytes(s.End + 1)}",
            Format.Bytes(s.Downloaded), s.Done ? "Done" : s.Active ? "Receiving" : "Waiting")).ToList();
        var done = _item.State == DownloadState.Completed;
        Title = done ? $"Complete · {_item.FileName}" : $"{_item.Fraction * 100:0}% · {_item.FileName}";
        ResumeRun.Text = _item.Kind == DownloadKind.Http ? (_item.Resumable ? "· resume supported" : "· server can't resume") : "";
        ToggleButton.Content = _item.IsActive || _item.State == DownloadState.Queued ? "Pause" : "Resume";
        ToggleButton.Visibility = done ? Visibility.Collapsed : Visibility.Visible;
        CancelButton.Visibility = done ? Visibility.Collapsed : Visibility.Visible;
        OpenButton.Visibility = done ? Visibility.Visible : Visibility.Collapsed;
    }

    void OnToggle(object sender, RoutedEventArgs e)
    {
        if (_item.IsActive || _item.State == DownloadState.Queued) _manager.Pause(_item);
        else _manager.Start(_item);
    }

    async void OnRemove(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(this, "Stop this download and remove its partial data?", "Remove download", MessageBoxButton.YesNo) != MessageBoxResult.Yes) return;
        await _manager.RemoveAsync(_item, deleteFile: false);
        Close();
    }

    void OnOpen(object sender, RoutedEventArgs e)
    {
        if (_item.LocalPath is { } path) Shell.Open(path);
    }

    void OnFolder(object sender, RoutedEventArgs e)
    {
        if (_item.LocalPath is { } path) Shell.ShowInFolder(path);
        else if (System.IO.Directory.Exists(_item.Folder)) Shell.Open(_item.Folder);
    }

    void OnLimitChanged(object sender, RoutedEventArgs e)
    {
        if (_item is null || LimitBox is null) return;
        var limit = LimitCheck.IsChecked == true && long.TryParse(LimitBox.Text.Trim(), out var kb) && kb > 0 ? kb * 1024 : 0;
        if (limit == _item.SpeedLimit) return;
        _item.SpeedLimit = limit;
        // The limiter is created when a transfer starts; restart a running one to apply it.
        if (_manager.IsRunning(_item))
        {
            _manager.Pause(_item);
            _ = Task.Delay(400).ContinueWith(_ => Dispatcher.Invoke(() => _manager.Start(_item)));
        }
    }

    void OnClose(object sender, RoutedEventArgs e) => Close();
}

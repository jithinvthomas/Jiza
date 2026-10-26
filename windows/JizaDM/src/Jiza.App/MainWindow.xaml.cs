using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Threading;
using Jiza.Core.Model;
using Jiza.Core.Queue;

namespace Jiza.App;

public sealed class SidebarEntry(string key, string label, string glyph, Func<DownloadItem, bool> match) : INotifyPropertyChanged
{
    public string Key { get; } = key;
    public string Label { get; } = label;
    public string Glyph { get; } = glyph;
    public Func<DownloadItem, bool> Match { get; } = match;
    int _count;
    public int Count { get => _count; set { if (_count != value) { _count = value; Changed(); } } }
    public event PropertyChangedEventHandler? PropertyChanged;
    void Changed([CallerMemberName] string name = "") => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public partial class MainWindow : Window
{
    public static readonly RoutedUICommand AddCommand = new(), PasteCommand = new(), DeleteCommand = new();

    readonly DownloadManager _manager;
    readonly ListCollectionView _view;
    readonly List<SidebarEntry> _entries;
    readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(1) };

    public MainWindow(DownloadManager manager)
    {
        _manager = manager;
        _entries =
        [
            new("all", "All downloads", "", _ => true),
            new("unfinished", "Unfinished", "", i => i.State != DownloadState.Completed),
            new("finished", "Finished", "", i => i.State == DownloadState.Completed),
            new("scheduled", "Scheduler queue", "", i => i.InSchedule && i.State != DownloadState.Completed),
            .. Categories.All.Select(c => new SidebarEntry(c, c, CategoryGlyphConverter.For(c), i => i.Category == c)),
        ];
        _view = (ListCollectionView)CollectionViewSource.GetDefaultView(manager.Items);
        InitializeComponent();
        Sidebar.ItemsSource = _entries;
        Sidebar.SelectedIndex = 0;

        _view.Filter = o => o is DownloadItem item && Matches(item);
        _view.IsLiveFiltering = true;
        _view.LiveFilteringProperties.Add(nameof(DownloadItem.State));
        _view.LiveFilteringProperties.Add(nameof(DownloadItem.Category));
        _view.LiveFilteringProperties.Add(nameof(DownloadItem.InSchedule));
        List.ItemsSource = _view;

        CommandBindings.Add(new CommandBinding(AddCommand, (_, _) => App.Current.ShowAddDialog(null)));
        CommandBindings.Add(new CommandBinding(PasteCommand, (_, _) => PasteLink()));
        CommandBindings.Add(new CommandBinding(DeleteCommand, (_, _) => OnDelete(this, new RoutedEventArgs())));
        _timer.Tick += (_, _) => Refresh();
        _timer.Start();
        Refresh();
        List.SizeChanged += (_, _) => FitColumns();
    }

    /// The File name column takes whatever width the other columns leave, so the list never scrolls sideways.
    void FitColumns()
    {
        if (List.View is not GridView grid) return;
        var others = grid.Columns.Where(c => c != NameColumn).Sum(c => double.IsNaN(c.Width) ? c.ActualWidth : c.Width);
        // Leave room for the vertical scrollbar and the list's own padding.
        NameColumn.Width = Math.Max(160, List.ActualWidth - others - 36);
    }

    bool Matches(DownloadItem item)
    {
        var entry = Sidebar.SelectedItem as SidebarEntry ?? _entries[0];
        if (!entry.Match(item)) return false;
        var query = Search.Text.Trim();
        return query.Length == 0 || item.FileName.Contains(query, StringComparison.OrdinalIgnoreCase) || item.Url.Contains(query, StringComparison.OrdinalIgnoreCase);
    }

    void Refresh()
    {
        var items = _manager.Snapshot();
        foreach (var entry in _entries) entry.Count = items.Count(entry.Match);
        var active = items.Count(i => i.IsActive);
        var speed = items.Where(i => i.IsActive).Sum(i => i.BytesPerSecond);
        StatusSpeed.Text = active > 0 ? "↓ " + Format.Speed(speed) : "Idle";
        StatusActive.Text = $"{active} active · {items.Count(i => i.State == DownloadState.Queued)} waiting · {items.Count(i => i.State == DownloadState.Completed)} finished";
        var settings = _manager.Settings;
        var flags = new List<string>();
        if (settings.GlobalSpeedLimit > 0) flags.Add("Speed limit " + Format.Speed(settings.GlobalSpeedLimit));
        flags.Add(settings.MonitorClipboard ? "Clipboard watch on" : "Clipboard watch off");
        if (settings.Schedule.Enabled) flags.Add($"Scheduler {settings.Schedule.StartAt:HH\\:mm}");
        flags.Add($"{settings.Connections} connections per file");
        StatusFlags.Text = string.Join("   ·   ", flags);
        EmptyState.Visibility = _view.IsEmpty ? Visibility.Visible : Visibility.Collapsed;
        Title = active > 0 ? $"Jiza Download Manager · {Format.Speed(speed)}" : "Jiza Download Manager";
    }

    List<DownloadItem> Selected => List.SelectedItems.OfType<DownloadItem>().ToList();

    void OnSidebarChanged(object sender, SelectionChangedEventArgs e) => RefreshFilter();
    void OnSearchChanged(object sender, TextChangedEventArgs e) => RefreshFilter();

    void RefreshFilter()
    {
        if (!IsInitialized || List is null) return;
        _view.Refresh();
        Refresh();
    }

    void OnAdd(object sender, RoutedEventArgs e) => App.Current.ShowAddDialog(null);
    void OnResume(object sender, RoutedEventArgs e) { foreach (var item in Selected.AsEnumerable().Reverse()) _manager.Start(item); }
    void OnPause(object sender, RoutedEventArgs e) { foreach (var item in Selected) _manager.Pause(item); }
    void OnPauseAll(object sender, RoutedEventArgs e) => _manager.PauseAll();
    void OnScheduler(object sender, RoutedEventArgs e) => new SchedulerWindow(_manager, App.Current.Scheduler) { Owner = this }.ShowDialog();
    void OnOptions(object sender, RoutedEventArgs e) => new SettingsWindow(_manager) { Owner = this }.ShowDialog();

    async void OnDelete(object sender, RoutedEventArgs e)
    {
        foreach (var item in Selected) await _manager.RemoveAsync(item, deleteFile: false);
    }

    async void OnDeleteWithFile(object sender, RoutedEventArgs e)
    {
        var items = Selected;
        if (items.Count == 0) return;
        var what = items.Count == 1 ? $"\"{items[0].FileName}\"" : $"{items.Count} downloads";
        if (MessageBox.Show(this, $"Delete {what} from your disk too? This can't be undone.", "Delete files", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        foreach (var item in items) await _manager.RemoveAsync(item, deleteFile: true);
    }

    async void OnClearFinished(object sender, RoutedEventArgs e)
    {
        foreach (var item in _manager.Snapshot().Where(i => i.State == DownloadState.Completed)) await _manager.RemoveAsync(item, deleteFile: false);
    }

    async void OnRestart(object sender, RoutedEventArgs e)
    {
        foreach (var item in Selected) await _manager.RestartAsync(item);
    }

    void OnDetails(object sender, RoutedEventArgs e)
    {
        if (Selected.FirstOrDefault() is { } item) DetailsWindow.ShowFor(_manager, item, this);
    }

    void OnToggleSchedule(object sender, RoutedEventArgs e)
    {
        var items = Selected;
        var add = items.Any(i => !i.InSchedule);
        foreach (var item in items) item.InSchedule = add;
        _view.Refresh();
        _manager.SaveNow();
    }

    void OnCopyUrl(object sender, RoutedEventArgs e)
    {
        if (Selected.FirstOrDefault() is not { } item) return;
        App.Current.IgnoreClipboard(item.Url);
        Clipboard.SetText(item.Url);
    }

    void OnContextOpened(object sender, RoutedEventArgs e)
    {
        var item = Selected.FirstOrDefault();
        MenuOpen.IsEnabled = item?.State == DownloadState.Completed;
        MenuFolder.IsEnabled = item is not null;
        MenuSchedule.Header = Selected.Any(i => !i.InSchedule) ? "Add to scheduler queue" : "Remove from scheduler queue";
    }

    void OnOpenFile(object sender, RoutedEventArgs e)
    {
        if (Selected.FirstOrDefault() is { LocalPath: { } path }) Shell.Open(path);
    }

    void OnOpenFolder(object sender, RoutedEventArgs e)
    {
        if (Selected.FirstOrDefault() is not { } item) return;
        if (item.LocalPath is { } path) Shell.ShowInFolder(path);
        else if (Directory.Exists(item.Folder)) Shell.Open(item.Folder);
    }

    void OnListDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (Selected.FirstOrDefault() is not { } item) return;
        if (item.State == DownloadState.Completed && item.LocalPath is { } path) Shell.Open(path);
        else DetailsWindow.ShowFor(_manager, item, this);
    }

    void PasteLink()
    {
        if (Keyboard.FocusedElement is TextBox) { ApplicationCommands.Paste.Execute(null, Keyboard.FocusedElement as IInputElement); return; }
        var text = Clipboard.ContainsText() ? Clipboard.GetText().Trim() : "";
        App.Current.ShowAddDialog(Uri.TryCreate(text, UriKind.Absolute, out _) ? new IncomingRequest { Url = text } : null);
    }

    void OnDragOver(object sender, DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) || e.Data.GetDataPresent(DataFormats.Text) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    void OnDrop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is string[] files)
        {
            foreach (var file in files.Where(f => f.EndsWith(".torrent", StringComparison.OrdinalIgnoreCase)))
                App.Current.ShowAddDialog(new IncomingRequest { Url = new Uri(Path.GetFullPath(file)).AbsoluteUri });
        }
        else if (e.Data.GetData(DataFormats.Text) is string text)
        {
            foreach (var line in text.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Take(50))
                if (Uri.TryCreate(line, UriKind.Absolute, out _)) App.Current.ShowAddDialog(new IncomingRequest { Url = line });
        }
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        // Like IDM, closing the window keeps Jiza running in the tray.
        if (!App.Current.IsExiting)
        {
            e.Cancel = true;
            Hide();
        }
        base.OnClosing(e);
    }
}

public static class Shell
{
    public static void Open(string path)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path) { UseShellExecute = true }); }
        catch (Exception e) when (e is Win32Exception or FileNotFoundException)
        { MessageBox.Show("Could not open " + path + ": " + e.Message, "Jiza"); }
    }

    public static void ShowInFolder(string path)
    {
        if (File.Exists(path) || Directory.Exists(path)) System.Diagnostics.Process.Start("explorer.exe", $"/select,\"{path}\"");
        else if (Path.GetDirectoryName(path) is { } dir && Directory.Exists(dir)) Open(dir);
    }
}

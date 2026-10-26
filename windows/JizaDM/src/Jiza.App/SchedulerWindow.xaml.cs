using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using Jiza.Core.Model;
using Jiza.Core.Queue;

namespace Jiza.App;

public partial class SchedulerWindow : Window
{
    readonly DownloadManager _manager;
    readonly Scheduler _scheduler;
    readonly Dictionary<DayOfWeek, CheckBox> _days = [];

    static readonly (WhenDoneAction Action, string Label)[] WhenDone =
    [
        (WhenDoneAction.Nothing, "Do nothing"),
        (WhenDoneAction.Exit, "Exit Jiza"),
        (WhenDoneAction.Sleep, "Put the PC to sleep"),
        (WhenDoneAction.Shutdown, "Shut down the PC (60 second warning)"),
    ];

    public SchedulerWindow(DownloadManager manager, Scheduler scheduler)
    {
        InitializeComponent();
        _manager = manager;
        _scheduler = scheduler;
        var schedule = manager.Settings.Schedule;
        EnabledBox.IsChecked = schedule.Enabled;
        StartBox.Text = schedule.StartAt.ToString("HH:mm", CultureInfo.InvariantCulture);
        StopEnabled.IsChecked = schedule.StopAt is not null;
        StopBox.Text = (schedule.StopAt ?? new TimeOnly(7, 0)).ToString("HH:mm", CultureInfo.InvariantCulture);
        var firstDay = CultureInfo.CurrentCulture.DateTimeFormat.FirstDayOfWeek;
        foreach (var day in Enumerable.Range(0, 7).Select(i => (DayOfWeek)(((int)firstDay + i) % 7)))
        {
            var box = new CheckBox { Content = CultureInfo.CurrentCulture.DateTimeFormat.GetAbbreviatedDayName(day), IsChecked = schedule.Days.Contains(day), Margin = new Thickness(0, 0, 10, 4), MinWidth = 0 };
            _days[day] = box;
            DaysPanel.Children.Add(box);
        }
        WhenDoneBox.ItemsSource = WhenDone.Select(w => w.Label).ToList();
        WhenDoneBox.SelectedIndex = Array.FindIndex(WhenDone, w => w.Action == schedule.WhenDone);
        var queued = manager.Snapshot().Count(i => i.InSchedule && i.State != DownloadState.Completed);
        QueueText.Text = queued == 0
            ? "The queue is empty. Use \"Download later\" or right-click a download > Add to scheduler queue."
            : $"{queued} download(s) in the scheduler queue.";
    }

    void OnStartNow(object sender, RoutedEventArgs e) => _scheduler.StartQueue();
    void OnStopNow(object sender, RoutedEventArgs e) => _scheduler.StopQueue();

    void OnSave(object sender, RoutedEventArgs e)
    {
        if (!TimeOnly.TryParseExact(StartBox.Text.Trim(), "H:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var start))
        { ErrorText.Text = "Enter the start time as HH:mm, for example 02:00."; return; }
        TimeOnly? stop = null;
        if (StopEnabled.IsChecked == true)
        {
            if (!TimeOnly.TryParseExact(StopBox.Text.Trim(), "H:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var s))
            { ErrorText.Text = "Enter the stop time as HH:mm, for example 07:00."; return; }
            stop = s;
        }
        var days = _days.Where(d => d.Value.IsChecked == true).Select(d => d.Key).ToArray();
        if (EnabledBox.IsChecked == true && days.Length == 0) { ErrorText.Text = "Choose at least one day."; return; }

        var settings = _manager.Settings;
        settings.Schedule = new ScheduleSettings
        {
            Enabled = EnabledBox.IsChecked == true,
            StartAt = start,
            StopAt = stop,
            Days = days,
            WhenDone = WhenDone[Math.Max(0, WhenDoneBox.SelectedIndex)].Action,
        };
        _manager.UpdateSettings(settings);
        DialogResult = true;
    }
}

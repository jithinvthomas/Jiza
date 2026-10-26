using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Threading;
using Jiza.Core.Model;
using Jiza.Core.Queue;

namespace Jiza.App;

/// Starts and stops the scheduled queue at set times, then runs the "when done" action.
public sealed class Scheduler
{
    readonly DownloadManager _manager;
    readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(15) };
    DateTime _lastCheck = DateTime.Now;

    public event Action<string>? Notify;
    public bool ShutdownPending { get; private set; }

    public Scheduler(DownloadManager manager)
    {
        _manager = manager;
        _timer.Tick += (_, _) => Check();
        _manager.ScheduleDrained += (_, _) => _timer.Dispatcher.BeginInvoke(RunWhenDone);
        _timer.Start();
    }

    ScheduleSettings Schedule => _manager.Settings.Schedule;

    void Check()
    {
        var now = DateTime.Now;
        var previous = _lastCheck;
        _lastCheck = now;
        if (!Schedule.Enabled || !Schedule.Days.Contains(now.DayOfWeek)) return;
        if (Crossed(previous, now, Schedule.StartAt)) StartQueue();
        if (Schedule.StopAt is { } stop && Crossed(previous, now, stop)) StopQueue();
    }

    static bool Crossed(DateTime from, DateTime to, TimeOnly at)
    {
        var target = to.Date + at.ToTimeSpan();
        if (target > to) target = target.AddDays(-1);
        return target > from && target <= to;
    }

    public void StartQueue()
    {
        var items = _manager.Snapshot().Where(i => i.InSchedule && i.CanStart).Reverse().ToList();
        foreach (var item in items) _manager.Start(item);
        if (items.Count > 0) Notify?.Invoke($"Scheduler started {items.Count} download(s).");
    }

    public void StopQueue()
    {
        foreach (var item in _manager.Snapshot().Where(i => i.InSchedule)) _manager.Pause(item);
        Notify?.Invoke("Scheduler paused the queue.");
    }

    void RunWhenDone()
    {
        switch (Schedule.WhenDone)
        {
            case WhenDoneAction.Exit:
                App.Current.ExitApp();
                break;
            case WhenDoneAction.Sleep:
                Notify?.Invoke("Downloads finished. Putting the PC to sleep.");
                SetSuspendState(false, false, false);
                break;
            case WhenDoneAction.Shutdown:
                // A 60 second delay leaves time to cancel from the tray menu.
                Process.Start(new ProcessStartInfo("shutdown", "/s /t 60 /c \"Jiza finished your downloads. Shutting down in 60 seconds.\"") { CreateNoWindow = true, UseShellExecute = false });
                ShutdownPending = true;
                Notify?.Invoke("Downloads finished. Windows shuts down in 60 seconds; use the tray menu to cancel.");
                break;
        }
    }

    public void CancelShutdown()
    {
        Process.Start(new ProcessStartInfo("shutdown", "/a") { CreateNoWindow = true, UseShellExecute = false });
        ShutdownPending = false;
        Notify?.Invoke("Shutdown cancelled.");
    }

    [DllImport("powrprof.dll", SetLastError = true)]
    static extern bool SetSuspendState(bool hibernate, bool forceCritical, bool disableWakeEvent);
}

using System.IO;
using System.Reflection;
using Forms = System.Windows.Forms;

namespace Jiza.App;

/// Notification-area icon: show, add, pause/resume all, speed limit, clipboard monitor, exit.
public sealed class Tray : IDisposable
{
    readonly Forms.NotifyIcon _icon;
    readonly Forms.ToolStripMenuItem _clipboard, _cancelShutdown;

    public Tray(App app)
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("jiza.ico")!;
        _icon = new Forms.NotifyIcon { Icon = new System.Drawing.Icon(stream), Text = "Jiza Download Manager", Visible = true };
        _icon.DoubleClick += (_, _) => app.ShowMain();

        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Open Jiza", null, (_, _) => app.ShowMain());
        menu.Items.Add("Add URL...", null, (_, _) => app.ShowAddDialog(null));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Resume all", null, (_, _) => app.Manager.StartAll());
        menu.Items.Add("Pause all", null, (_, _) => app.Manager.PauseAll());
        var speed = new Forms.ToolStripMenuItem("Speed limit");
        foreach (var (label, bytes) in new[] { ("Unlimited", 0L), ("10 MB/s", 10L << 20), ("5 MB/s", 5L << 20), ("2 MB/s", 2L << 20), ("1 MB/s", 1L << 20), ("500 KB/s", 500L << 10) })
            speed.DropDownItems.Add(label, null, (_, _) => app.SetSpeedLimit(bytes));
        menu.Items.Add(speed);
        var theme = new Forms.ToolStripMenuItem("Theme");
        foreach (var (label, value) in new[] { ("Follow Windows", Theme.System), ("Light", Theme.Light), ("Dark", Theme.Dark) })
            theme.DropDownItems.Add(new Forms.ToolStripMenuItem(label, null, (_, _) => app.SetTheme(value)) { Tag = value });
        theme.DropDownOpening += (_, _) =>
        {
            foreach (Forms.ToolStripMenuItem item in theme.DropDownItems) item.Checked = (string)item.Tag! == Theme.Current;
        };
        menu.Items.Add(theme);
        _clipboard = new Forms.ToolStripMenuItem("Watch clipboard for links") { CheckOnClick = true };
        _clipboard.Click += (_, _) => app.SetClipboardMonitor(_clipboard.Checked);
        menu.Items.Add(_clipboard);
        _cancelShutdown = new Forms.ToolStripMenuItem("Cancel scheduled shutdown", null, (_, _) => app.Scheduler.CancelShutdown()) { Visible = false };
        menu.Items.Add(_cancelShutdown);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => app.ExitApp());
        menu.Opening += (_, _) =>
        {
            _clipboard.Checked = app.Manager.Settings.MonitorClipboard;
            _cancelShutdown.Visible = app.Scheduler.ShutdownPending;
        };
        _icon.ContextMenuStrip = menu;
    }

    public void UpdateTooltip(double speed, int active)
    {
        var text = active > 0 ? $"Jiza: {active} downloading, {Format.Speed(speed)}" : "Jiza Download Manager";
        _icon.Text = text.Length > 63 ? text[..63] : text;
    }

    public void Balloon(string title, string message, Action? onClick = null)
    {
        _icon.BalloonTipTitle = title;
        _icon.BalloonTipText = message;
        if (onClick is not null)
        {
            void Handler(object? s, EventArgs e) { _icon.BalloonTipClicked -= Handler; onClick(); }
            _icon.BalloonTipClicked += Handler;
        }
        _icon.ShowBalloonTip(4000);
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
    }
}

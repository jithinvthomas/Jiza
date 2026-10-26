using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Jiza.Core;

namespace Jiza.App;

/// Watches the clipboard for copied download links (AddClipboardFormatListener on a message-only window).
public sealed class ClipboardMonitor : IDisposable
{
    const int WmClipboardUpdate = 0x031D;
    readonly HwndSource _source;
    string? _last;

    public event Action<string>? LinkCopied;
    public bool Enabled { get; set; } = true;
    /// Set before copying a link from inside Jiza so it doesn't offer to download it again.
    public string? Ignore { get; set; }

    public ClipboardMonitor()
    {
        _source = new HwndSource(new HwndSourceParameters("JizaClipboard") { ParentWindow = new IntPtr(-3), WindowStyle = 0 });
        _source.AddHook(WndProc);
        AddClipboardFormatListener(_source.Handle);
    }

    IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmClipboardUpdate && Enabled) _source.Dispatcher.BeginInvoke(Check);
        return IntPtr.Zero;
    }

    void Check()
    {
        string? text = null;
        // Another app may still hold the clipboard open.
        for (var attempt = 0; attempt < 3 && text is null; attempt++)
        {
            try { text = Clipboard.ContainsText() ? Clipboard.GetText().Trim() : ""; }
            catch (COMException) { Thread.Sleep(30); }
        }
        if (string.IsNullOrEmpty(text) || text == _last) return;
        _last = text;
        if (text == Ignore) { Ignore = null; return; }
        if (DownloadPolicy.IsMonitoredLink(text)) LinkCopied?.Invoke(text);
    }

    public void Dispose()
    {
        RemoveClipboardFormatListener(_source.Handle);
        _source.Dispose();
    }

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool AddClipboardFormatListener(IntPtr hwnd);

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool RemoveClipboardFormatListener(IntPtr hwnd);
}

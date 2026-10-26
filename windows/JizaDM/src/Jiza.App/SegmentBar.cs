using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using Jiza.Core.Model;

namespace Jiza.App;

/// The Jiza segment ribbon: each byte range a connection owns is a lane in one bar, filled in cobalt,
/// with an amber "write head" glowing where an active connection is writing right now.
/// Bind Item for a self-refreshing ribbon (list rows), or call Update (details window).
public sealed class SegmentBar : FrameworkElement
{
    public static readonly DependencyProperty ItemProperty = DependencyProperty.Register(
        nameof(Item), typeof(DownloadItem), typeof(SegmentBar), new PropertyMetadata(null, (d, _) => ((SegmentBar)d).Refresh()));

    /// One timer drives every ribbon on screen, so long lists stay cheap.
    static readonly DispatcherTimer Ticker = new() { Interval = TimeSpan.FromMilliseconds(400) };
    static event EventHandler? Tick;

    static SegmentBar() => Ticker.Tick += (_, e) => Tick?.Invoke(null, e);

    Segment[] _segments = [];
    long _total;
    double _fraction;
    bool _complete;

    public SegmentBar()
    {
        Loaded += (_, _) => { Tick += OnTick; Ticker.Start(); };
        Unloaded += (_, _) => Tick -= OnTick;
    }

    public DownloadItem? Item
    {
        get => (DownloadItem?)GetValue(ItemProperty);
        set => SetValue(ItemProperty, value);
    }

    void OnTick(object? sender, EventArgs e)
    {
        // Finished and idle ribbons don't change; skip the redraw.
        if (Item is { IsActive: true }) Refresh();
    }

    void Refresh()
    {
        if (Item is not { } item) return;
        Update(item.SnapshotSegments(), item.TotalBytes, item.Fraction, item.State == DownloadState.Completed);
    }

    public void Update(Segment[] segments, long total, double fraction, bool complete = false)
    {
        _segments = segments;
        _total = total;
        _fraction = fraction;
        _complete = complete;
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext dc)
    {
        var width = ActualWidth;
        var height = ActualHeight;
        if (width <= 0 || height <= 0) return;
        var radius = Math.Min(4, height / 2);
        var lanes = height >= 10;
        var track = Theme.Brush("JizaTrack");
        var done = Theme.Brush("JizaCobalt");
        var head = Theme.Brush("JizaFilament");

        dc.DrawRoundedRectangle(track, null, new Rect(0, 0, width, height), radius, radius);
        dc.PushClip(new RectangleGeometry(new Rect(0, 0, width, height), radius, radius));
        if (_complete)
        {
            dc.DrawRectangle(done, null, new Rect(0, 0, width, height));
        }
        else if (_total <= 0 || _segments.Length == 0)
        {
            // No byte layout (streams, torrents, unknown size): one lane of overall progress.
            dc.DrawRectangle(done, null, new Rect(0, 0, width * Math.Clamp(_fraction, 0, 1), height));
        }
        else
        {
            var divider = new Pen(Theme.Brush("JizaSurface"), 1);
            foreach (var segment in _segments)
            {
                var x = width * segment.Start / _total;
                var w = width * segment.Downloaded / _total;
                if (w > 0) dc.DrawRectangle(done, null, new Rect(x, 0, w, height));
                if (lanes && segment.Start > 0) dc.DrawLine(divider, new Point(x, 0), new Point(x, height));
                if (segment.Active && !segment.Done)
                {
                    // The write head: a bright amber edge with a soft glow behind it.
                    var edge = x + w;
                    if (lanes)
                    {
                        // The glow only on the large ribbon; on list rows it reads as noise.
                        var glow = new SolidColorBrush(((SolidColorBrush)head).Color) { Opacity = 0.28 };
                        dc.DrawRectangle(glow, null, new Rect(edge - 5, 0, 7, height));
                    }
                    dc.DrawRectangle(head, null, new Rect(edge - 1, 0, lanes ? 3 : 1.25, height));
                }
            }
        }
        dc.Pop();
    }
}

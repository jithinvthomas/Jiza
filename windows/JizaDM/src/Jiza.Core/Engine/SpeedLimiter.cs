using System.Diagnostics;

namespace Jiza.Core.Engine;

/// Token bucket shared by every connection it is passed to. A limit of 0 means unlimited.
public sealed class SpeedLimiter
{
    readonly object _gate = new();
    readonly Stopwatch _clock = Stopwatch.StartNew();
    double _tokens;
    double _last;

    public long BytesPerSecond { get; set; }

    public SpeedLimiter(long bytesPerSecond = 0) => BytesPerSecond = bytesPerSecond;

    public async ValueTask WaitAsync(int bytes, CancellationToken ct)
    {
        while (true)
        {
            var limit = BytesPerSecond;
            if (limit <= 0) return;
            TimeSpan delay;
            lock (_gate)
            {
                var now = _clock.Elapsed.TotalSeconds;
                // Cap the burst at a quarter second of traffic so pauses don't bank unlimited credit.
                _tokens = Math.Min(limit / 4.0 + bytes, _tokens + (now - _last) * limit);
                _last = now;
                if (_tokens >= bytes) { _tokens -= bytes; return; }
                delay = TimeSpan.FromSeconds((bytes - _tokens) / limit);
            }
            await Task.Delay(delay < TimeSpan.FromMilliseconds(5) ? TimeSpan.FromMilliseconds(5) : delay, ct);
        }
    }
}

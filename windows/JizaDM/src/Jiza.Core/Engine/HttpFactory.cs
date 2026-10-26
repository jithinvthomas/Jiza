using System.Net;
using System.Net.Sockets;
using Jiza.Core.Model;

namespace Jiza.Core.Engine;

public static class HttpFactory
{
    static readonly TimeSpan AttemptDelay = TimeSpan.FromMilliseconds(250);

    /// Tuned for throughput: every segment gets its own TCP connection. HTTP/2 is avoided on purpose,
    /// because it multiplexes all ranges onto one connection and loses the multi-connection speed-up.
    public static HttpClient Create(DownloadSettings settings)
    {
        var handler = new SocketsHttpHandler
        {
            MaxConnectionsPerServer = 256,
            AllowAutoRedirect = true,
            MaxAutomaticRedirections = 20,
            // Ranges address the encoded bytes; decompression would break offsets.
            AutomaticDecompression = DecompressionMethods.None,
            UseCookies = false,
            ConnectTimeout = TimeSpan.FromSeconds(15),
            PooledConnectionLifetime = TimeSpan.FromMinutes(10),
            PooledConnectionIdleTimeout = TimeSpan.FromSeconds(60),
            ConnectCallback = HappyEyeballsAsync,
        };
        if (!string.IsNullOrWhiteSpace(settings.Proxy))
        {
            handler.Proxy = new WebProxy(settings.Proxy);
            handler.UseProxy = true;
        }
        return new HttpClient(handler)
        {
            Timeout = Timeout.InfiniteTimeSpan,
            DefaultRequestVersion = HttpVersion.Version11,
            DefaultVersionPolicy = HttpVersionPolicy.RequestVersionOrLower,
        };
    }

    /// RFC 8305 "Happy Eyeballs": race IPv6 and IPv4 addresses, starting a new attempt every 250 ms.
    /// Without it, a host with a dead IPv6 route stalls until the connect timeout even though IPv4 works.
    static async ValueTask<Stream> HappyEyeballsAsync(SocketsHttpConnectionContext context, CancellationToken ct)
    {
        var endpoint = context.DnsEndPoint;
        var addresses = IPAddress.TryParse(endpoint.Host, out var literal)
            ? [literal]
            : await Dns.GetHostAddressesAsync(endpoint.Host, ct);
        var ordered = Interleave(addresses);
        if (ordered.Count == 0) throw new SocketException((int)SocketError.HostNotFound);

        using var race = CancellationTokenSource.CreateLinkedTokenSource(ct);
        var pending = new List<Task<Socket>>();
        Exception? lastError = null;
        var next = 0;
        var startNext = true;
        while (pending.Count > 0 || next < ordered.Count)
        {
            if (startNext && next < ordered.Count) pending.Add(ConnectAsync(ordered[next++], endpoint.Port, race.Token));
            var waits = new List<Task>(pending);
            Task? timer = next < ordered.Count ? Task.Delay(AttemptDelay, race.Token) : null;
            if (timer is not null) waits.Add(timer);
            var finished = await Task.WhenAny(waits);
            if (finished == timer) { startNext = true; continue; }

            var attempt = (Task<Socket>)finished;
            pending.Remove(attempt);
            if (attempt.IsCompletedSuccessfully)
            {
                race.Cancel();
                foreach (var loser in pending) _ = loser.ContinueWith(t => { if (t.IsCompletedSuccessfully) t.Result.Dispose(); }, TaskScheduler.Default);
                return new NetworkStream(attempt.Result, ownsSocket: true);
            }
            lastError = attempt.Exception?.InnerException ?? lastError;
            // A failed attempt frees the next address immediately instead of waiting for the timer.
            startNext = true;
        }
        ct.ThrowIfCancellationRequested();
        throw lastError ?? new SocketException((int)SocketError.HostUnreachable);
    }

    static async Task<Socket> ConnectAsync(IPAddress address, int port, CancellationToken ct)
    {
        var socket = new Socket(address.AddressFamily, SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
        try
        {
            await socket.ConnectAsync(new IPEndPoint(address, port), ct);
            return socket;
        }
        catch
        {
            socket.Dispose();
            throw;
        }
    }

    /// Alternates address families, IPv6 first, as RFC 8305 recommends.
    static List<IPAddress> Interleave(IPAddress[] addresses)
    {
        var v6 = new Queue<IPAddress>(addresses.Where(a => a.AddressFamily == AddressFamily.InterNetworkV6));
        var v4 = new Queue<IPAddress>(addresses.Where(a => a.AddressFamily == AddressFamily.InterNetwork));
        var result = new List<IPAddress>(addresses.Length);
        while (v6.Count > 0 || v4.Count > 0)
        {
            if (v6.TryDequeue(out var a)) result.Add(a);
            if (v4.TryDequeue(out var b)) result.Add(b);
        }
        return result;
    }
}

using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;

namespace Jiza.App;

/// Chrome/Edge native messaging host. The browser starts JizaDM.exe with the extension origin as the first
/// argument and exchanges length-prefixed JSON on stdin/stdout. Each message is forwarded to the running app.
public static class NativeHost
{
    public static bool IsNativeHostLaunch(string[] args) =>
        args.Length > 0 && args[0].StartsWith("chrome-extension://", StringComparison.OrdinalIgnoreCase);

    public static async Task<int> RunAsync()
    {
        await using var input = Console.OpenStandardInput();
        await using var output = Console.OpenStandardOutput();
        App.Trace("native host started");
        while (await ReadAsync(input) is { } message)
        {
            App.Trace("native host received " + message.Length + " bytes");
            object reply;
            try
            {
                var request = JsonSerializer.Deserialize<IncomingRequest>(message, IncomingRequest.Json);
                if (request is null) reply = new { ok = false, error = "Empty message" };
                else if (request.Type == "ping") reply = new { ok = true, version = typeof(NativeHost).Assembly.GetName().Version?.ToString(3), running = await Ipc.SendAsync(new IncomingRequest { Type = "ping" }, TimeSpan.FromMilliseconds(300)) };
                else reply = await ForwardAsync(request) ? new { ok = true } : new { ok = false, error = "Jiza Download Manager did not respond." };
            }
            catch (JsonException e) { reply = new { ok = false, error = e.Message }; }
            App.Trace("native host replied " + JsonSerializer.Serialize(reply));
            await WriteAsync(output, JsonSerializer.Serialize(reply));
        }
        return 0;
    }

    static async Task<bool> ForwardAsync(IncomingRequest request)
    {
        if (await Ipc.SendAsync(request, TimeSpan.FromSeconds(2))) return true;
        // The app isn't running: start it in the tray, then retry while it boots.
        if (Environment.ProcessPath is { } exe) Process.Start(new ProcessStartInfo(exe, "--tray") { UseShellExecute = false });
        for (var i = 0; i < 20; i++)
        {
            await Task.Delay(500);
            if (await Ipc.SendAsync(request, TimeSpan.FromSeconds(1))) return true;
        }
        return false;
    }

    static async Task<string?> ReadAsync(Stream input)
    {
        var header = new byte[4];
        if (!await FillAsync(input, header)) return null;
        var length = BitConverter.ToInt32(header);
        if (length is <= 0 or > 4 * 1024 * 1024) return null;
        var body = new byte[length];
        return await FillAsync(input, body) ? Encoding.UTF8.GetString(body) : null;
    }

    static async Task<bool> FillAsync(Stream input, byte[] buffer)
    {
        var read = 0;
        while (read < buffer.Length)
        {
            var n = await input.ReadAsync(buffer.AsMemory(read));
            if (n == 0) return false;
            read += n;
        }
        return true;
    }

    static async Task WriteAsync(Stream output, string json)
    {
        var body = Encoding.UTF8.GetBytes(json);
        await output.WriteAsync(BitConverter.GetBytes(body.Length));
        await output.WriteAsync(body);
        await output.FlushAsync();
    }
}

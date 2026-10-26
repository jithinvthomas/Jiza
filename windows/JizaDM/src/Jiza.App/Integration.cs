using System.IO;
using System.Reflection;
using System.Text.Json;
using Jiza.Core;
using Microsoft.Win32;

namespace Jiza.App;

/// Per-user (HKCU) registration: browser native messaging host, jiza:// links, start with Windows,
/// and unpacking the bundled browser extension.
public static class Integration
{
    public const string HostName = "com.jiza.dm";
    /// Fixed by the "key" in extension/manifest.json.
    public const string ExtensionId = "ajdhdfdokfleaaafolicdlbafcfhdhne";

    static readonly string[] BrowserHostKeys =
    [
        @"Software\Google\Chrome\NativeMessagingHosts\",
        @"Software\Microsoft\Edge\NativeMessagingHosts\",
        @"Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\",
        @"Software\Chromium\NativeMessagingHosts\",
        @"Software\Vivaldi\NativeMessagingHosts\",
    ];

    public static string ExePath => Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "JizaDM.exe");
    public static string ExtensionFolder => Path.Combine(Store.DefaultDataFolder, "extension");
    static string ManifestPath => Path.Combine(Store.DefaultDataFolder, "native-host", HostName + ".json");

    /// Safe to run on every start: keeps the registered exe path current if the app moved.
    public static void Register()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(ManifestPath)!);
        var manifest = new
        {
            name = HostName,
            description = "Jiza Download Manager",
            path = ExePath,
            type = "stdio",
            allowed_origins = new[] { $"chrome-extension://{ExtensionId}/" },
        };
        File.WriteAllText(ManifestPath, JsonSerializer.Serialize(manifest, new JsonSerializerOptions { WriteIndented = true }));
        foreach (var key in BrowserHostKeys)
        {
            using var host = Registry.CurrentUser.CreateSubKey(key + HostName);
            host.SetValue("", ManifestPath);
        }

        using (var protocol = Registry.CurrentUser.CreateSubKey(@"Software\Classes\jiza"))
        {
            protocol.SetValue("", "URL:Jiza Download");
            protocol.SetValue("URL Protocol", "");
            using var icon = protocol.CreateSubKey("DefaultIcon");
            icon.SetValue("", $"\"{ExePath}\",0");
            using var command = protocol.CreateSubKey(@"shell\open\command");
            command.SetValue("", $"\"{ExePath}\" \"%1\"");
        }
        UnpackExtension();
    }

    public static bool IsRegistered()
    {
        using var key = Registry.CurrentUser.OpenSubKey(BrowserHostKeys[0] + HostName);
        return key?.GetValue("") is string path && File.Exists(path);
    }

    public static void Unregister()
    {
        foreach (var key in BrowserHostKeys) Registry.CurrentUser.DeleteSubKeyTree(key + HostName, throwOnMissingSubKey: false);
        Registry.CurrentUser.DeleteSubKeyTree(@"Software\Classes\jiza", throwOnMissingSubKey: false);
        SetStartWithWindows(false);
    }

    public static void SetStartWithWindows(bool enabled)
    {
        using var run = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        if (enabled) run.SetValue("JizaDM", $"\"{ExePath}\" --tray");
        else run.DeleteValue("JizaDM", throwOnMissingValue: false);
    }

    /// Writes the extension files embedded in the exe, so "Load unpacked" has a stable folder to point at.
    public static void UnpackExtension()
    {
        var assembly = Assembly.GetExecutingAssembly();
        foreach (var name in assembly.GetManifestResourceNames().Where(n => n.StartsWith("extension/")))
        {
            var relative = name["extension/".Length..].Replace('/', Path.DirectorySeparatorChar).Replace('\\', Path.DirectorySeparatorChar);
            var target = Path.Combine(ExtensionFolder, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            using var source = assembly.GetManifestResourceStream(name)!;
            using var file = File.Create(target);
            source.CopyTo(file);
        }
    }

    /// Parses jiza://download?url=... links and bare URLs or .torrent paths passed on the command line.
    public static IncomingRequest? FromArgument(string arg)
    {
        if (arg.StartsWith("jiza:", StringComparison.OrdinalIgnoreCase) && Uri.TryCreate(arg, UriKind.Absolute, out var jiza))
        {
            var query = System.Web.HttpUtility.ParseQueryString(jiza.Query);
            return query["url"] is { Length: > 0 } url ? new IncomingRequest { Url = url, FileName = query["name"], Referrer = query["referrer"] } : null;
        }
        if (File.Exists(arg) && arg.EndsWith(".torrent", StringComparison.OrdinalIgnoreCase))
            return new IncomingRequest { Url = new Uri(Path.GetFullPath(arg)).AbsoluteUri };
        return Uri.TryCreate(arg, UriKind.Absolute, out var uri) && (uri.Scheme is "http" or "https" or "ftp" or "ftps" or "magnet")
            ? new IncomingRequest { Url = arg }
            : null;
    }
}

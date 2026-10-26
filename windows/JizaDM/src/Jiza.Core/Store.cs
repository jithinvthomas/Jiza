using System.Text.Json;
using System.Text.Json.Serialization;
using Jiza.Core.Model;

namespace Jiza.Core;

/// JSON persistence in %AppData%\JizaDM: downloads.json (the list, with segment state) and settings.json.
public sealed class Store(string folder)
{
    public static string DefaultDataFolder { get; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "JizaDM");

    static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    readonly object _gate = new();
    public string Folder { get; } = folder;
    string DownloadsPath => Path.Combine(Folder, "downloads.json");
    string SettingsPath => Path.Combine(Folder, "settings.json");

    public List<DownloadItem> LoadDownloads() => Load<List<DownloadItem>>(DownloadsPath) ?? [];
    public DownloadSettings LoadSettings() => Load<DownloadSettings>(SettingsPath) ?? new DownloadSettings();

    public void SaveDownloads(IEnumerable<DownloadItem> items)
    {
        // Segment lists are mutated by worker threads; serialize consistent copies.
        var snapshot = items.Select(i => (Item: i, Segments: i.SnapshotSegments())).ToList();
        lock (_gate)
        {
            using var stream = new MemoryStream();
            using (var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true }))
            {
                writer.WriteStartArray();
                foreach (var (item, segments) in snapshot)
                {
                    JsonElement element;
                    lock (item.SegmentLock) element = JsonSerializer.SerializeToElement(item, Options);
                    writer.WriteStartObject();
                    foreach (var property in element.EnumerateObject())
                    {
                        if (property.Name == nameof(DownloadItem.Segments))
                        {
                            writer.WritePropertyName(property.Name);
                            JsonSerializer.Serialize(writer, segments, Options);
                        }
                        else property.WriteTo(writer);
                    }
                    writer.WriteEndObject();
                }
                writer.WriteEndArray();
            }
            WriteAtomic(DownloadsPath, stream.ToArray());
        }
    }

    public void SaveSettings(DownloadSettings settings)
    {
        lock (_gate) WriteAtomic(SettingsPath, JsonSerializer.SerializeToUtf8Bytes(settings, Options));
    }

    T? Load<T>(string path) where T : class
    {
        try
        {
            if (!File.Exists(path)) return null;
            ReadOnlySpan<byte> json = File.ReadAllBytes(path);
            // Notepad and PowerShell save UTF-8 with a byte-order mark, which the JSON reader rejects.
            if (json.StartsWith((ReadOnlySpan<byte>)[0xEF, 0xBB, 0xBF])) json = json[3..];
            return JsonSerializer.Deserialize<T>(json, Options);
        }
        catch (JsonException)
        {
            // Keep the unreadable file for inspection instead of silently overwriting it.
            File.Copy(path, path + ".corrupt", overwrite: true);
            return null;
        }
    }

    void WriteAtomic(string path, byte[] bytes)
    {
        Directory.CreateDirectory(Folder);
        var temp = path + ".tmp";
        File.WriteAllBytes(temp, bytes);
        File.Move(temp, path, overwrite: true);
    }
}

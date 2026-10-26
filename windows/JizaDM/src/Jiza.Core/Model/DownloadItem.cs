using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;

namespace Jiza.Core.Model;

public enum DownloadState { Queued, Connecting, Downloading, Paused, Failed, Saving, Completed }

public enum DownloadKind { Http, Ftp, Hls, Media, Torrent }

public sealed class Segment
{
    public long Start { get; set; }
    /// Inclusive end offset.
    public long End { get; set; }
    public long Downloaded { get; set; }
    [JsonIgnore] public bool Active { get; set; }
    [JsonIgnore] public long Position => Start + Downloaded;
    [JsonIgnore] public long Remaining => Math.Max(0, End - Position + 1);
    [JsonIgnore] public bool Done => Position > End;
}

/// One entry in the download list. Mirrors the lifecycle of Jiza's BrowserDownload.
public sealed class DownloadItem : INotifyPropertyChanged
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Url { get => _url; set => Set(ref _url, value); }
    public DownloadKind Kind { get => _kind; set => Set(ref _kind, value); }
    public string FileName { get => _fileName; set => Set(ref _fileName, value); }
    public string Folder { get; set; } = "";
    public string Category { get => _category; set => Set(ref _category, value); }
    /// Request headers kept for retries and resume: Cookie, Referer, User-Agent, Authorization.
    public Dictionary<string, string> Headers { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public int Connections { get; set; } = 16;
    public long SpeedLimit { get; set; }
    /// yt-dlp format selector or HLS variant chosen in the add dialog.
    public string? MediaFormat { get; set; }
    public bool InSchedule { get; set; }
    public DateTime AddedAt { get; set; } = DateTime.Now;
    public DateTime? CompletedAt { get => _completedAt; set => Set(ref _completedAt, value); }
    /// ETag or Last-Modified captured on the first response; sent as If-Range on resume.
    public string? Validator { get; set; }
    public string? LocalPath { get => _localPath; set => Set(ref _localPath, value); }
    public string? PartPath { get; set; }
    public List<Segment> Segments { get; set; } = [];
    public bool Resumable { get => _resumable; set => Set(ref _resumable, value); }

    public DownloadState State
    {
        get => _state;
        set { if (Set(ref _state, value)) { OnChanged(nameof(IsActive)); OnChanged(nameof(CanStart)); OnChanged(nameof(Fraction)); } }
    }
    public string Status { get => _status; set => Set(ref _status, value); }
    public long TotalBytes { get => _total; set { if (Set(ref _total, value)) OnChanged(nameof(Fraction)); } }
    public long DownloadedBytes { get => _downloaded; set { if (Set(ref _downloaded, value)) OnChanged(nameof(Fraction)); } }
    /// Explicit progress for kinds whose byte total is unknown (HLS segments, torrents).
    public double? ProgressOverride { get => _progress; set { if (Set(ref _progress, value)) OnChanged(nameof(Fraction)); } }

    [JsonIgnore] public double BytesPerSecond { get => _speed; set { if (Set(ref _speed, value)) OnChanged(nameof(Eta)); } }
    [JsonIgnore] public int ActiveConnections { get => _activeConnections; set => Set(ref _activeConnections, value); }
    [JsonIgnore] public bool IsActive => State is DownloadState.Connecting or DownloadState.Downloading or DownloadState.Saving;
    [JsonIgnore] public bool CanStart => State is DownloadState.Queued or DownloadState.Paused or DownloadState.Failed;
    [JsonIgnore]
    public double Fraction => State == DownloadState.Completed ? 1
        : ProgressOverride ?? (TotalBytes > 0 ? Math.Clamp((double)DownloadedBytes / TotalBytes, 0, 1) : 0);
    [JsonIgnore]
    public TimeSpan? Eta => BytesPerSecond > 1 && TotalBytes > 0 && DownloadedBytes < TotalBytes
        ? TimeSpan.FromSeconds((TotalBytes - DownloadedBytes) / BytesPerSecond) : null;

    /// Guards Segments; workers split and advance segments concurrently.
    [JsonIgnore] public object SegmentLock { get; } = new();

    public Segment[] SnapshotSegments()
    {
        lock (SegmentLock)
            return Segments.Select(s => new Segment { Start = s.Start, End = s.End, Downloaded = s.Downloaded, Active = s.Active }).ToArray();
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    void OnChanged(string name) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    bool Set<T>(ref T field, T value, [CallerMemberName] string name = "")
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnChanged(name);
        return true;
    }

    string _url = "", _fileName = "", _category = Categories.Other, _status = "Queued";
    string? _localPath;
    DownloadKind _kind;
    DownloadState _state = DownloadState.Queued;
    long _total = -1, _downloaded;
    double _speed;
    double? _progress;
    int _activeConnections;
    bool _resumable;
    DateTime? _completedAt;
}

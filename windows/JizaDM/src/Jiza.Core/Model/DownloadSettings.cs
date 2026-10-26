namespace Jiza.Core.Model;

public enum WhenDoneAction { Nothing, Exit, Sleep, Shutdown }

public sealed class ScheduleSettings
{
    public bool Enabled { get; set; }
    public TimeOnly StartAt { get; set; } = new(2, 0);
    public TimeOnly? StopAt { get; set; } = new(7, 0);
    public DayOfWeek[] Days { get; set; } = Enum.GetValues<DayOfWeek>();
    public WhenDoneAction WhenDone { get; set; }
}

public sealed class DownloadSettings
{
    public string DownloadFolder { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "Jiza");
    public bool UseCategoryFolders { get; set; } = true;
    public int Connections { get; set; } = 16;
    public int MaxConcurrent { get; set; } = 3;
    /// Bytes per second across all downloads; 0 = unlimited.
    public long GlobalSpeedLimit { get; set; }
    public bool MonitorClipboard { get; set; } = true;
    public bool CaptureBrowserDownloads { get; set; } = true;
    public bool StartWithoutAsking { get; set; }
    public bool ShowCompleteDialog { get; set; } = true;
    public bool StartWithWindows { get; set; }
    /// Upload/download ratio to seed torrents to after completion; 0 = stop when complete.
    public double SeedRatio { get; set; }
    public string? Proxy { get; set; }
    public string UserAgent { get; set; } = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36";
    public ScheduleSettings Schedule { get; set; } = new();
    /// "System" (follow Windows), "Light" or "Dark".
    public string Theme { get; set; } = "System";
    /// Version of the license the user agreed to; null until the first-run agreement.
    public string? AcceptedLicense { get; set; }

    public string FolderFor(string category) => UseCategoryFolders ? Path.Combine(DownloadFolder, category) : DownloadFolder;
}

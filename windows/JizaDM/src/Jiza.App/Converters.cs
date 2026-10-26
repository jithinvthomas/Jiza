using System.Globalization;
using System.Windows.Data;
using System.Windows.Media;
using Jiza.Core.Model;

namespace Jiza.App;

public static class Format
{
    public static string Bytes(long bytes)
    {
        if (bytes < 0) return "Unknown";
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        double value = bytes;
        var unit = 0;
        while (value >= 1024 && unit < units.Length - 1) { value /= 1024; unit++; }
        return unit == 0 ? $"{bytes} B" : value.ToString(value >= 100 ? "0" : value >= 10 ? "0.0" : "0.00", CultureInfo.CurrentCulture) + " " + units[unit];
    }

    public static string Speed(double bytesPerSecond) => bytesPerSecond < 1 ? "" : Bytes((long)bytesPerSecond) + "/s";

    public static string Eta(TimeSpan? eta)
    {
        if (eta is not { } t) return "";
        if (t.TotalDays >= 1) return $"{(int)t.TotalDays}d {t.Hours}h";
        if (t.TotalHours >= 1) return $"{(int)t.TotalHours}h {t.Minutes}m";
        if (t.TotalMinutes >= 1) return $"{t.Minutes}m {t.Seconds}s";
        return $"{Math.Max(1, t.Seconds)}s";
    }
}

public sealed class BytesConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => value is long b ? Format.Bytes(b) : "";
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}

public sealed class SpeedConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => value is double s ? Format.Speed(s) : "";
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}

public sealed class EtaConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => Format.Eta(value as TimeSpan?);
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}

public sealed class PercentConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is double f ? (f * 100).ToString(f >= 0.995 ? "0" : "0.0", culture) + "%" : "";
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}

public sealed class StateBrushConverter : IValueConverter
{
    // Theme brushes are recoloured in place, so these follow light/dark switches.
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => value switch
    {
        DownloadState.Completed => Theme.Brush("JizaSuccess"),
        DownloadState.Failed => Theme.Brush("JizaDanger"),
        DownloadState.Connecting or DownloadState.Downloading or DownloadState.Saving => Theme.Brush("JizaAccent"),
        _ => Theme.Brush("JizaMuted"),
    };
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}

public sealed class CategoryGlyphConverter : IValueConverter
{
    public static string For(string? category) => category switch
    {
        Categories.Video => "",
        Categories.Music => "",
        Categories.Documents => "",
        Categories.Compressed => "",
        Categories.Programs => "",
        Categories.Torrents => "",
        _ => "",
    };
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => For(value as string);
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}

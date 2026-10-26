using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace Jiza.App;

/// Light, dark or follow-Windows appearance. Palettes come from the Jiza app's JizaDesign.swift.
/// The app brushes are recoloured in place, so every open window updates without a restart.
public static class Theme
{
    public const string System = "System", Light = "Light", Dark = "Dark";
    public static readonly string[] Choices = [System, Light, Dark];

    static readonly Dictionary<string, (string Light, string Dark)> Palette = new()
    {
        ["JizaBackground"] = ("#EFF3FF", "#10182C"),
        ["JizaSurface"] = ("#FFFFFF", "#19243D"),
        ["JizaSurfaceRaised"] = ("#E4EAFB", "#213052"),
        ["JizaBorder"] = ("#D3DCF3", "#2C3D66"),
        ["JizaCobalt"] = ("#315BEB", "#315BEB"),
        ["JizaAccent"] = ("#315BEB", "#91B3FF"),
        ["JizaText"] = ("#14203D", "#EEF2FF"),
        ["JizaMuted"] = ("#5B6785", "#9AA8C7"),
        ["JizaSuccess"] = ("#1E8E50", "#5BD68A"),
        ["JizaDanger"] = ("#C93636", "#FF7A7A"),
        ["JizaWarning"] = ("#A86A12", "#FFC966"),
        ["JizaTrack"] = ("#DCE3F7", "#213052"),
        // Filament: the one warm colour, reserved for live write heads.
        ["JizaFilament"] = ("#F5A524", "#FFB547"),
    };

    public static string Current { get; private set; } = System;
    public static bool IsDark { get; private set; } = true;
    static bool _listening;

    public static void Apply(string? choice)
    {
        Current = Choices.Contains(choice) ? choice! : System;
        IsDark = Current switch { Light => false, Dark => true, _ => !WindowsUsesLightTheme() };
        var app = Application.Current;
        app.ThemeMode = IsDark ? ThemeMode.Dark : ThemeMode.Light;
        foreach (var (key, colors) in Palette) Recolor(app.Resources, key, Parse(IsDark ? colors.Dark : colors.Light));
        // XAML-loaded gradient stops are read-only, so the backdrop is replaced; windows bind it with DynamicResource.
        app.Resources["JizaBackdrop"] = new RadialGradientBrush(
            IsDark ? Color.FromArgb(0x3A, 0x31, 0x5B, 0xEB) : Color.FromArgb(0x2E, 0x31, 0x5B, 0xEB),
            IsDark ? Color.FromArgb(0, 0x10, 0x18, 0x2C) : Color.FromArgb(0, 0xEF, 0xF3, 0xFF))
        { Center = new Point(1, 0), GradientOrigin = new Point(1, 0), RadiusX = 0.9, RadiusY = 1.2 };
        if (!_listening)
        {
            // Follow Windows when the user switches light/dark while Jiza is open.
            SystemEvents.UserPreferenceChanged += (_, e) =>
            {
                if (e.Category == UserPreferenceCategory.General && Current == System) app.Dispatcher.BeginInvoke(() => Apply(System));
            };
            _listening = true;
        }
    }

    public static Brush Brush(string key) => (Brush)Application.Current.Resources[key];

    static void Recolor(ResourceDictionary resources, string key, Color color)
    {
        if (resources[key] is SolidColorBrush { IsFrozen: false } brush) brush.Color = color;
        else resources[key] = new SolidColorBrush(color);
    }

    static Color Parse(string hex) => (Color)ColorConverter.ConvertFromString(hex);

    static bool WindowsUsesLightTheme()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("AppsUseLightTheme") is int value && value == 1;
    }
}

using System.IO;
using System.Reflection;
using System.Windows;

namespace Jiza.App;

/// Shows the freeware EULA for acceptance on first start, or read-only from Options > About.
public partial class LicenseWindow : Window
{
    /// Bump when LICENSE.txt changes so users see the new terms once.
    public const string CurrentVersion = "1.0";

    public LicenseWindow(string resource, bool askToAccept)
    {
        InitializeComponent();
        Body.Text = Read(resource);
        if (!askToAccept)
        {
            Heading.Text = resource == "notices.txt" ? "Third-party notices" : "License";
            Intro.Text = resource == "notices.txt"
                ? "Open-source components included in Jiza and the licenses they are used under."
                : "The terms you accepted for Jiza Download Manager.";
            DeclineButton.Visibility = Visibility.Collapsed;
            AgreeButton.Content = "Close";
        }
    }

    public static string Read(string resource)
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resource);
        return stream is null ? "" : new StreamReader(stream).ReadToEnd();
    }

    void OnAgree(object sender, RoutedEventArgs e) => DialogResult = true;
    void OnDecline(object sender, RoutedEventArgs e) => DialogResult = false;
}

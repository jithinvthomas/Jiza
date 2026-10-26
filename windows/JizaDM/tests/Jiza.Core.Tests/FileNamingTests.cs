namespace Jiza.Core.Tests;

/// Cases ported from Jiza's BrowserModelTests plus Windows-specific ones.
public class FileNamingTests
{
    [Theory]
    [InlineData("../../movie.mp4", "movie.mp4")]
    [InlineData("..\\..\\movie.mp4", "movie.mp4")]
    [InlineData("..", "download")]
    [InlineData("", "download")]
    [InlineData("a\u0007b.zip", "ab.zip")]
    [InlineData("what?.pdf", "what.pdf")]
    [InlineData("CON.txt", "download")]
    [InlineData("name. ", "name")]
    public void SafeStripsPathsAndUnsafeCharacters(string input, string expected) =>
        Assert.Equal(expected, FileNaming.Safe(input));

    [Fact]
    public void SafeCapsLength() => Assert.Equal(180, FileNaming.Safe(new string('a', 300)).Length);

    [Fact]
    public void UnusedPathNumbersCollisions()
    {
        var taken = new HashSet<string> { Path.Combine("d", "movie.mp4"), Path.Combine("d", "movie (2).mp4") };
        Assert.Equal(Path.Combine("d", "movie (3).mp4"), FileNaming.UnusedPath("d", "../movie.mp4", taken.Contains));
    }

    [Theory]
    [InlineData("attachment; filename=\"plain.zip\"", "plain.zip")]
    [InlineData("attachment; filename=fallback.zip; filename*=UTF-8''r%C3%A9sum%C3%A9.pdf", "résumé.pdf")]
    [InlineData("inline", null)]
    public void ParsesContentDisposition(string header, string? expected) =>
        Assert.Equal(expected, FileNaming.ParseContentDisposition(header));

    [Fact]
    public void FallsBackToUrlAndMimeExtension()
    {
        Assert.Equal("my file.iso", FileNaming.FromResponse(new Uri("https://x.test/a/my%20file.iso?t=1"), null, null));
        Assert.Equal("video.mp4", FileNaming.FromResponse(new Uri("https://x.test/video"), null, "video/mp4"));
    }
}

public class StoreTests
{
    [Fact]
    public void ReadsFilesSavedWithByteOrderMark()
    {
        var folder = Directory.CreateTempSubdirectory("jiza-store-").FullName;
        try
        {
            // As Notepad or PowerShell would save a hand-edited file.
            File.WriteAllText(Path.Combine(folder, "settings.json"), "{\"Connections\": 8}", new System.Text.UTF8Encoding(true));
            File.WriteAllText(Path.Combine(folder, "downloads.json"), "[]", new System.Text.UTF8Encoding(true));
            var store = new Store(folder);
            Assert.Equal(8, store.LoadSettings().Connections);
            Assert.Empty(store.LoadDownloads());
            Assert.False(File.Exists(Path.Combine(folder, "downloads.json.corrupt")));
        }
        finally { Directory.Delete(folder, recursive: true); }
    }
}

public class DownloadPolicyTests
{
    [Fact]
    public void PortedJizaPolicy()
    {
        Assert.True(DownloadPolicy.ShouldDownload("video/mp4", null, mainFrame: true, enabled: true));
        Assert.True(DownloadPolicy.ShouldDownload("audio/mpeg", null, mainFrame: true, enabled: true));
        Assert.False(DownloadPolicy.ShouldDownload("video/mp4", null, mainFrame: false, enabled: true));
        Assert.False(DownloadPolicy.ShouldDownload("video/mp4", null, mainFrame: true, enabled: false));
        Assert.False(DownloadPolicy.ShouldDownload("text/html", null, mainFrame: true, enabled: true));
        Assert.True(DownloadPolicy.ShouldDownload("text/html", "attachment; filename=x", mainFrame: false, enabled: false));
        Assert.True(DownloadPolicy.IsFileLink(new Uri("https://example.com/file.torrent?token=123")));
    }

    [Theory]
    [InlineData("https://example.com/setup.exe", true)]
    [InlineData("magnet:?xt=urn:btih:abc", true)]
    [InlineData("ftp://host/file.bin", true)]
    [InlineData("https://example.com/page.html", false)]
    [InlineData("not a url", false)]
    [InlineData("https://a.test/x.zip\nhttps://b.test/y.zip", false)]
    public void ClipboardMonitorRecognisesLinks(string text, bool expected) =>
        Assert.Equal(expected, DownloadPolicy.IsMonitoredLink(text));

    [Theory]
    [InlineData("magnet:?xt=urn:btih:abc&dn=x", Model.DownloadKind.Torrent)]
    [InlineData("https://a.test/x.torrent", Model.DownloadKind.Torrent)]
    [InlineData("ftp://a.test/x.iso", Model.DownloadKind.Ftp)]
    [InlineData("https://a.test/live/index.m3u8", Model.DownloadKind.Hls)]
    [InlineData("https://www.youtube.com/watch?v=abc", Model.DownloadKind.Media)]
    [InlineData("https://a.test/x.zip", Model.DownloadKind.Http)]
    public void GuessesKind(string url, Model.DownloadKind kind) => Assert.Equal(kind, Engine.LinkAnalyzer.GuessKind(url));
}

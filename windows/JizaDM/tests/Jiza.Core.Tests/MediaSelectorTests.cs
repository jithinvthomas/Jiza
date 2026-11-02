using Jiza.Core.Engine;

namespace Jiza.Core.Tests;

public class MediaSelectorTests
{
    static MediaChoice Best => new("Best quality", MediaStreamKind.Video, null, -1);
    static MediaChoice At(int h) => new($"{h}p", MediaStreamKind.Video, h, -1);
    static MediaChoice Audio => new("Audio only", MediaStreamKind.Audio, null, -1);
    static MediaFormatOption Fmt(string? v) => new(v ?? "Original", v);

    [Fact]
    public void VideoMp4WithFfmpegPrefersMp4AndMergesToMp4()
    {
        var plan = MediaSelector.Build(Best, Fmt("mp4"), hasFfmpeg: true);
        Assert.Equal("mp4", plan.MergeContainer);
        Assert.Null(plan.AudioCodec);
        Assert.StartsWith("bv*[ext=mp4]+ba[ext=m4a]", plan.Selector);
    }

    [Fact]
    public void VideoWithHeightConstrainsResolution()
    {
        var plan = MediaSelector.Build(At(1080), Fmt("mp4"), hasFfmpeg: true);
        Assert.Contains("[height<=1080]", plan.Selector);
        Assert.Equal("mp4", plan.MergeContainer);
    }

    [Fact]
    public void VideoWebmAndMkvSetTheirContainers()
    {
        Assert.Equal("webm", MediaSelector.Build(Best, Fmt("webm"), hasFfmpeg: true).MergeContainer);
        Assert.Equal("mkv", MediaSelector.Build(Best, Fmt("mkv"), hasFfmpeg: true).MergeContainer);
    }

    [Fact]
    public void VideoOriginalDoesNotForceAContainer()
    {
        var plan = MediaSelector.Build(Best, Fmt(null), hasFfmpeg: true);
        Assert.Null(plan.MergeContainer);
        Assert.Equal("bv*+ba/b", plan.Selector);
    }

    [Fact]
    public void VideoWithoutFfmpegTakesASinglePreMergedFileAndNeverMerges()
    {
        var plan = MediaSelector.Build(At(1080), Fmt("mp4"), hasFfmpeg: false);
        Assert.Null(plan.MergeContainer);
        Assert.Null(plan.AudioCodec);
        Assert.Equal("b[height<=1080][ext=mp4]/b[height<=1080]/b", plan.Selector);
    }

    [Theory]
    [InlineData("mp3", "ba/b")]
    [InlineData("wav", "ba/b")]
    [InlineData("m4a", "ba[ext=m4a]/ba/b")]
    public void AudioWithFfmpegExtractsToChosenCodec(string codec, string expectedSelector)
    {
        var plan = MediaSelector.Build(Audio, Fmt(codec), hasFfmpeg: true);
        Assert.Equal(expectedSelector, plan.Selector);
        Assert.Equal(codec, plan.AudioCodec);
        Assert.Null(plan.MergeContainer);
    }

    [Fact]
    public void AudioOriginalWithFfmpegKeepsNativeAudio()
    {
        var plan = MediaSelector.Build(Audio, Fmt(null), hasFfmpeg: true);
        Assert.Equal("ba/b", plan.Selector);
        Assert.Null(plan.AudioCodec);
    }

    [Fact]
    public void AudioWithoutFfmpegGrabsBestAudioWithoutConverting()
    {
        var plan = MediaSelector.Build(Audio, Fmt(null), hasFfmpeg: false);
        Assert.Equal("ba[acodec!=none]/b", plan.Selector);
        Assert.Null(plan.AudioCodec);
        Assert.Null(plan.MergeContainer);
    }

    [Fact]
    public void FormatOptionListsNarrowWithoutFfmpeg()
    {
        Assert.Equal(4, MediaSelector.VideoContainers(hasFfmpeg: true).Count);
        Assert.Equal(2, MediaSelector.VideoContainers(hasFfmpeg: false).Count);
        Assert.Single(MediaSelector.AudioCodecs(hasFfmpeg: false));
    }
}

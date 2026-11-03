namespace Jiza.Core.Engine;

public enum MediaStreamKind { Video, Audio }

/// A quality row in the Add dialog: a resolution, "Best", or "Audio only".
public sealed record MediaChoice(string Label, MediaStreamKind Kind, int? Height, long EstimatedBytes);

/// A container (video) or codec (audio) row paired with a MediaChoice to build the yt-dlp plan.
/// Value is the yt-dlp container/codec name, or null for "keep whatever yt-dlp picks".
public sealed record MediaFormatOption(string Label, string? Value);

/// The three things yt-dlp needs: the -f selector, an optional --merge-output-format, and an optional -x audio codec.
public sealed record MediaPlan(string Selector, string? MergeContainer, string? AudioCodec);

/// Turns a user's quality + format choice into a yt-dlp plan. Kept pure so it can be unit-tested.
public static class MediaSelector
{
    /// Containers offered for a video quality. Merging needs ffmpeg, so without it only a single file is possible.
    public static IReadOnlyList<MediaFormatOption> VideoContainers(bool hasFfmpeg) =>
        hasFfmpeg
            ? [new("MP4 (recommended)", "mp4"), new("WebM", "webm"), new("MKV (any codec)", "mkv"), new("Original", null)]
            : [new("MP4 if available", "mp4"), new("Original", null)];

    /// Codecs offered for "Audio only". Converting needs ffmpeg, so without it we keep the native audio.
    public static IReadOnlyList<MediaFormatOption> AudioCodecs(bool hasFfmpeg) =>
        hasFfmpeg
            ? [new("MP3", "mp3"), new("M4A / AAC", "m4a"), new("WAV", "wav"), new("Original", null)]
            : [new("Original", null)];

    public static MediaPlan Build(MediaChoice choice, MediaFormatOption format, bool hasFfmpeg)
    {
        if (choice.Kind == MediaStreamKind.Audio)
        {
            // Without ffmpeg we can't transcode, so grab the best audio-only stream as-is.
            if (!hasFfmpeg) return new MediaPlan("ba[acodec!=none]/b", null, null);
            var codec = format.Value;                       // mp3 / m4a / wav / null (= keep native)
            var selector = codec == "m4a" ? "ba[ext=m4a]/ba/b" : "ba/b";
            return new MediaPlan(selector, null, codec);
        }

        var h = choice.Height is int height ? $"[height<={height}]" : "";
        var container = format.Value;                       // mp4 / webm / mkv / null

        // Without ffmpeg we can't merge separate video+audio, so only a single pre-merged file will play.
        if (!hasFfmpeg)
        {
            var single = container == "mp4" ? $"b{h}[ext=mp4]/b{h}/b" : $"b{h}/b";
            return new MediaPlan(single, null, null);
        }

        return container switch
        {
            // Prefer MP4 video + M4A audio so the result is a widely-playable .mp4, not a .webm.
            "mp4" => new MediaPlan($"bv*{h}[ext=mp4]+ba[ext=m4a]/bv*{h}+ba/b{h}/bv*+ba/b", "mp4", null),
            "webm" => new MediaPlan($"bv*{h}[ext=webm]+ba[ext=webm]/bv*{h}+ba/b{h}", "webm", null),
            "mkv" => new MediaPlan($"bv*{h}+ba/b{h}", "mkv", null),
            _ => new MediaPlan($"bv*{h}+ba/b{h}", null, null),
        };
    }
}

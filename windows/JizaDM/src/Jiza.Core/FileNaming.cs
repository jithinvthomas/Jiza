namespace Jiza.Core;

/// Ported from Jiza's BrowserDownloads.safeFilename / unusedURL.
public static class FileNaming
{
    public const string Fallback = "download";

    public static string Safe(string? name)
    {
        var basename = (name ?? "").Replace('\\', '/').Split('/').Last();
        var invalid = Path.GetInvalidFileNameChars();
        var clean = new string(basename.Where(c => !char.IsControl(c) && !invalid.Contains(c)).ToArray()).Trim().TrimEnd('.');
        if (clean.Length > 180) clean = clean[..180];
        return clean.Length == 0 || clean == "." || clean == ".." || IsReservedDeviceName(clean) ? Fallback : clean;
    }

    /// Returns a path in `directory` that does not exist yet: "name.ext", then "name (2).ext", ...
    public static string UnusedPath(string directory, string name, Func<string, bool>? exists = null)
    {
        exists ??= p => File.Exists(p) || Directory.Exists(p);
        var safe = Safe(name);
        var initial = Path.Combine(directory, safe);
        if (!exists(initial)) return initial;
        var stem = Path.GetFileNameWithoutExtension(safe);
        var ext = Path.GetExtension(safe);
        for (var i = 2; i < 10_000; i++)
        {
            var candidate = Path.Combine(directory, $"{stem} ({i}){ext}");
            if (!exists(candidate)) return candidate;
        }
        return Path.Combine(directory, Guid.NewGuid().ToString("N") + "-" + safe);
    }

    /// Atomically claims a new empty file, so concurrent downloads never pick the same path.
    public static string Reserve(string directory, string name)
    {
        for (var attempt = 0; attempt < 100; attempt++)
        {
            var path = UnusedPath(directory, name);
            try
            {
                using (new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.ReadWrite)) { }
                return path;
            }
            catch (IOException) when (File.Exists(path)) { }
        }
        throw new IOException($"Could not find a free file name for {name} in {directory}.");
    }

    /// Moves a finished file to an unused name, retrying if another download takes the name first.
    public static string MoveToUnused(string source, string directory, string name)
    {
        for (var attempt = 0; attempt < 100; attempt++)
        {
            var target = UnusedPath(directory, name);
            try
            {
                File.Move(source, target, overwrite: false);
                return target;
            }
            catch (IOException) when (File.Exists(target)) { }
        }
        throw new IOException($"Could not find a free file name for {name} in {directory}.");
    }

    /// Filename from Content-Disposition, falling back to the last URL path segment.
    public static string FromResponse(Uri url, string? contentDisposition, string? mime)
    {
        var name = ParseContentDisposition(contentDisposition);
        if (string.IsNullOrWhiteSpace(name))
        {
            var last = url.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries).LastOrDefault() ?? "";
            name = Uri.UnescapeDataString(last);
        }
        name = Safe(name);
        if (string.IsNullOrEmpty(Path.GetExtension(name)) && DownloadPolicy.ExtensionForMime(mime) is { } ext)
            name += "." + ext;
        return name;
    }

    public static string? ParseContentDisposition(string? header)
    {
        if (string.IsNullOrWhiteSpace(header)) return null;
        string? plain = null;
        foreach (var raw in header.Split(';'))
        {
            var part = raw.Trim();
            var eq = part.IndexOf('=');
            if (eq < 0) continue;
            var key = part[..eq].Trim().ToLowerInvariant();
            var value = part[(eq + 1)..].Trim().Trim('"');
            if (key == "filename*")
            {
                // RFC 5987: charset'lang'percent-encoded
                var quote = value.IndexOf("''", StringComparison.Ordinal);
                var encoded = quote >= 0 ? value[(quote + 2)..] : value;
                try { return Uri.UnescapeDataString(encoded); } catch (UriFormatException) { }
            }
            else if (key == "filename") plain = value;
        }
        return plain;
    }

    static bool IsReservedDeviceName(string name)
    {
        var stem = Path.GetFileNameWithoutExtension(name).ToUpperInvariant();
        return stem is "CON" or "PRN" or "AUX" or "NUL" || (stem.Length == 4 && (stem.StartsWith("COM") || stem.StartsWith("LPT")) && char.IsDigit(stem[3]));
    }
}

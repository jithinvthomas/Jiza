using System.Buffers;
using FluentFTP;
using Jiza.Core.Model;

namespace Jiza.Core.Engine;

/// FTP/FTPS downloads with resume (REST). Credentials come from the URL: ftp://user:pass@host/path.
public sealed class FtpDownloader : IDownloader
{
    public DownloadKind Kind => DownloadKind.Ftp;

    static AsyncFtpClient Client(Uri url)
    {
        var user = "anonymous";
        var password = "anonymous@";
        if (!string.IsNullOrEmpty(url.UserInfo))
        {
            var parts = url.UserInfo.Split(':', 2);
            user = Uri.UnescapeDataString(parts[0]);
            password = parts.Length > 1 ? Uri.UnescapeDataString(parts[1]) : "";
        }
        var client = new AsyncFtpClient(url.Host, user, password, url.IsDefaultPort || url.Port <= 0 ? 21 : url.Port);
        if (url.Scheme == "ftps") client.Config.EncryptionMode = FtpEncryptionMode.Explicit;
        client.Config.ConnectTimeout = 15_000;
        client.Config.ReadTimeout = 30_000;
        client.Config.DataConnectionReadTimeout = 30_000;
        return client;
    }

    static string RemotePath(Uri url) => Uri.UnescapeDataString(url.AbsolutePath);

    public static async Task<long> SizeAsync(Uri url, CancellationToken ct)
    {
        try
        {
            await using var client = Client(url);
            await client.Connect(ct);
            return await client.GetFileSize(RemotePath(url), -1, ct);
        }
        catch (Exception e) when (e is not OperationCanceledException) { return -1; }
    }

    public async Task RunAsync(DownloadItem item, DownloadContext ctx, CancellationToken ct)
    {
        var url = new Uri(item.Url);
        item.State = DownloadState.Connecting;
        item.Status = "Connecting to FTP server";
        await using var client = Client(url);
        try { await client.Connect(ct); }
        catch (Exception e) when (e is not OperationCanceledException)
        { throw new DownloadException("Could not sign in to the FTP server: " + e.Message, retryable: true, e); }

        var path = RemotePath(url);
        item.TotalBytes = await client.GetFileSize(path, -1, ct);
        if (string.IsNullOrWhiteSpace(item.FileName)) item.FileName = FileNaming.Safe(Path.GetFileName(path));
        Directory.CreateDirectory(item.Folder);
        item.PartPath ??= FileNaming.Reserve(item.Folder, item.FileName + ".jdpart");
        var existing = File.Exists(item.PartPath) ? new FileInfo(item.PartPath).Length : 0;
        if (item.TotalBytes > 0 && existing > item.TotalBytes) existing = 0;
        item.Resumable = true;

        var limiter = item.SpeedLimit > 0 ? new SpeedLimiter(item.SpeedLimit) : null;
        var buffer = ArrayPool<byte>.Shared.Rent(256 * 1024);
        try
        {
            await using var file = new FileStream(item.PartPath, existing > 0 ? FileMode.Append : FileMode.Create, FileAccess.Write, FileShare.Read, 256 * 1024, useAsync: true);
            await using (var remote = await client.OpenRead(path, FtpDataType.Binary, existing, true, ct))
            {
                item.State = DownloadState.Downloading;
                item.Status = existing > 0 ? "Resuming" : "Downloading";
                item.ActiveConnections = 1;
                var done = existing;
                int read;
                while ((read = await remote.ReadAsync(buffer, ct)) > 0)
                {
                    await file.WriteAsync(buffer.AsMemory(0, read), ct);
                    done += read;
                    item.DownloadedBytes = done;
                    await ctx.ThrottleAsync(limiter, read, ct);
                }
            }
            if (item.TotalBytes > 0 && file.Length < item.TotalBytes)
                throw new DownloadException("The FTP server closed the connection early.", retryable: true);
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buffer);
            item.ActiveConnections = 0;
        }

        var final = FileNaming.MoveToUnused(item.PartPath, item.Folder, item.FileName);
        item.LocalPath = final;
        item.FileName = Path.GetFileName(final);
        item.PartPath = null;
        item.TotalBytes = item.DownloadedBytes = new FileInfo(final).Length;
    }
}

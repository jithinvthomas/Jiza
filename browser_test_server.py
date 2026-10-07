"""Loopback-only fixtures for the iPhone browser integration tests."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        route = self.path.split("?", 1)[0]
        if route == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/inline-video")
            self.end_headers()
            return
        mime, disposition = "text/html", None
        if route in ("/movie.mp4", "/inline-video"):
            body, mime = Path("TestFixtures/sample-video.mp4").read_bytes(), "video/mp4"
        elif route == "/song.mp3":
            body, mime = Path("TestFixtures/without-artwork.mp3").read_bytes(), "audio/mpeg"
        elif route == "/fixture.torrent":
            body, mime = b"d8:announce19:https://example.come", "application/x-bittorrent"
        elif route == "/links":
            body = b'<html><title>Download links</title><a id="video" target="_blank" href="/movie.mp4">Video</a><a id="audio" href="/song.mp3">Audio</a><a id="redirect" target="_blank" href="/redirect">Redirect</a><a id="torrent" href="/fixture.torrent">Torrent</a></html>'
        elif route == "/ads/banner.js":
            body, mime = b"window.jizaAdLoaded = true;", "application/javascript"
        elif route == "/ad-test":
            body = b'<html><title>Ad test</title><script src="/ads/banner.js"></script><body>Content</body></html>'
        elif route == "/file":
            body, mime, disposition = b"Jiza downloaded file fixture", "application/octet-stream", "attachment; filename=fixture.txt"
        else:
            body = b"<html><head><title>Jiza test page</title></head><body>Browser fixture</body></html>"
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if disposition: self.send_header("Content-Disposition", disposition)
        else: self.send_header("Set-Cookie", "jiza_test=yes; Path=/; SameSite=Lax")
        self.end_headers()
        self.wfile.write(body)

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()

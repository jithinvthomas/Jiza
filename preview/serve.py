"""Local-only Jiza design preview. Serves a fixed asset allowlist, never the repository."""
import argparse
import hashlib
import mimetypes
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent
ASSETS = {
    **{f"lettering-{name}.png": f"Brand/jiza-lettering-{name}-v1.png" for name in ["music", "video", "browser", "download", "trading"]},
    "symbol.png": "Assets.xcassets/JizaSymbol.imageset/jiza-symbol.png",
    "wordmark.png": "Assets.xcassets/JizaWordmark.imageset/wordmark.png",
    "music.png": "Assets.xcassets/JizaPlayer.imageset/logo.png",
    "video.png": "Assets.xcassets/JizaVideo.imageset/logo.png",
    "browser.png": "Assets.xcassets/JizaBrowser.imageset/logo.png",
    "trading.png": "Assets.xcassets/JizaTrading.imageset/logo.png",
    "sample.mp4": "TestFixtures/sample-video.mp4",
    "sample.mp3": "TestFixtures/with-artwork.mp3",
}

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        route = urlsplit(self.path).path
        if route == "/version":
            value = "|".join(str((ROOT / name).stat().st_mtime_ns) for name in ["index.html", "style.css", "app.js"])
            self.send_bytes(hashlib.sha256(value.encode()).hexdigest().encode(), "text/plain")
            return
        file = None
        if route in ["/", "/index.html", "/style.css", "/app.js"]:
            file = ROOT / ("index.html" if route == "/" else route[1:])
        elif route.startswith("/assets/") and route[8:] in ASSETS:
            file = PROJECT / ASSETS[route[8:]]
        if file is None or not file.is_file():
            self.send_error(404)
            return
        self.send_bytes(file.read_bytes(), mimetypes.guess_type(file.name)[0] or "application/octet-stream")

    def send_bytes(self, data, mime):
        self.send_response(200)
        self.send_header("Content-Type", mime + ("; charset=utf-8" if mime.startswith("text/") else ""))
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self'; media-src 'self'; connect-src 'self'; object-src 'none'; frame-ancestors 'self'")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        pass

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8789)
    args = parser.parse_args()
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()

"""Loopback-only fixtures for the iPhone browser integration tests."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        is_file = self.path == "/file"
        body = (b"Jiza downloaded file fixture" if is_file else
                b"<html><head><title>Jiza test page</title></head><body>Browser fixture</body></html>")
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream" if is_file else "text/html")
        self.send_header("Content-Length", str(len(body)))
        if is_file:
            self.send_header("Content-Disposition", "attachment; filename=fixture.txt")
        else:
            self.send_header("Set-Cookie", "jiza_test=yes; Path=/; SameSite=Lax")
        self.end_headers()
        self.wfile.write(body)

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()

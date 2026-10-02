"""Error-discovery review server (stdlib only)."""
import json, os
from http.server import HTTPServer, SimpleHTTPRequestHandler

BASE = os.path.dirname(os.path.abspath(__file__))
FILES = {"samples", "annotations", "patterns", "suggestions"}


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=BASE, **kw)

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/":
            self.path = "/index.html"
            return super().do_GET()
        name = self.path.removeprefix("/api/")
        if self.path.startswith("/api/") and name in FILES:
            with open(os.path.join(BASE, f"{name}.json")) as f:
                return self._json(json.load(f))
        return super().do_GET()

    def do_POST(self):
        name = self.path.removeprefix("/api/")
        if not (self.path.startswith("/api/") and name in FILES):
            return self._json({"error": "unknown"}, 404)
        length = int(self.headers.get("Content-Length", 0))
        data = json.loads(self.rfile.read(length))
        with open(os.path.join(BASE, f"{name}.json"), "w") as f:
            json.dump(data, f, indent=1)
        return self._json({"ok": True})

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print("review app on http://localhost:8377")
    HTTPServer(("127.0.0.1", 8377), Handler).serve_forever()

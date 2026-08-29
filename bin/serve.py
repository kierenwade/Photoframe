#!/usr/bin/env python3
"""Tiny local web server for the kiosk. Stdlib only.

Routes:
  /                 -> app/index.html and static assets
  /config.json      -> the browser-relevant slice of config.toml, rendered live
  /manifest.json    -> /data/photos/manifest.json (written by sync.py)
  /photos/<name>    -> /data/photos/processed/<name>

Bound to localhost only; Chromium opens http://localhost:8080/.
"""
from __future__ import annotations

import json
import os
import tomllib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"
CONF = ROOT / "config.toml"
# on the Pi this is /data/photos; override for local dev with FRAME_PHOTOS_DIR
PHOTOS = Path(os.environ.get("FRAME_PHOTOS_DIR", "/data/photos"))
PROCESSED = PHOTOS / "processed"
PORT = int(os.environ.get("FRAME_PORT", "8080"))


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(APP), **kwargs)

    # quieter logs
    def log_message(self, fmt, *args):  # noqa: A003
        pass

    def _send_json(self, obj: object, status: int = 200) -> None:
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _client_config(self) -> dict:
        c = tomllib.loads(CONF.read_text())
        return {
            "slideshow": c.get("slideshow", {}),
            "display": c.get("display", {}),
            "dimming": c.get("dimming", {}),
        }

    def do_GET(self):  # noqa: N802
        path = self.path.split("?", 1)[0]

        if path == "/config.json":
            try:
                return self._send_json(self._client_config())
            except Exception as e:  # noqa: BLE001
                return self._send_json({"error": str(e)}, 500)

        if path == "/manifest.json":
            mf = PHOTOS / "manifest.json"
            if mf.exists():
                try:
                    return self._send_json(json.loads(mf.read_text()))
                except Exception:  # noqa: BLE001
                    pass
            return self._send_json({"generated": None, "count": 0, "photos": []})

        if path.startswith("/photos/"):
            name = Path(path[len("/photos/"):]).name  # no traversal
            f = PROCESSED / name
            if f.is_file():
                data = f.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(data)
                return
            self.send_error(404)
            return

        return super().do_GET()

    do_HEAD = do_GET


def main() -> None:
    ThreadingHTTPServer.allow_reuse_address = True
    with ThreadingHTTPServer(("127.0.0.1", PORT), Handler) as httpd:
        print(f"serving on http://127.0.0.1:{PORT}", flush=True)
        httpd.serve_forever()


if __name__ == "__main__":
    main()

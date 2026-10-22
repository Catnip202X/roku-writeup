#!/usr/bin/env python3
"""
roku-debloat/collector.py — capture probe reports and browser beacons from the TV.

    ./collector.py --port 8899

GET  /beacon?ua=...   logged (JS from the Roku browser engine proves it executes)
POST /report          body appended to loot/report-<ts>.txt (BrightScript exfil)
GET  /health          "ok"
"""
import argparse
import datetime
import json
import pathlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = pathlib.Path(__file__).resolve().parent
LOOT = HERE / "loot"
LOOT.mkdir(exist_ok=True)


class Handler(BaseHTTPRequestHandler):
    def _log(self, kind, data):
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        path = LOOT / f"{kind}-{stamp}.txt"
        with path.open("a") as fh:
            fh.write(json.dumps(data, indent=2, default=str) + "\n")
        print(f"[{stamp}] {kind}: {json.dumps(data, default=str)[:400]}", flush=True)

    def do_GET(self):
        if self.path.startswith("/health"):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
            return
        self._log("beacon", {
            "path": self.path,
            "ua": self.headers.get("User-Agent"),
            "origin": self.headers.get("Origin"),
            "headers": dict(self.headers),
            "client": self.client_address[0],
        })
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(b"ok")

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        if self.path.startswith("/ca"):
            # raw sink for large blobs (CA bundles) — written verbatim, no JSON wrapper
            out = LOOT / "ca-bundle.pem"
            out.write_bytes(body)
            print(f"[ca] wrote {len(body)} bytes -> {out}", flush=True)
        else:
            self._log("report", {
                "path": self.path,
                "body": body.decode("latin-1"),
                "ua": self.headers.get("User-Agent"),
                "client": self.client_address[0],
            })
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8899)
    ap.add_argument("--bind", default="0.0.0.0")
    a = ap.parse_args()
    srv = ThreadingHTTPServer((a.bind, a.port), Handler)
    print(f"collector on {a.bind}:{a.port} -> {LOOT}", flush=True)
    srv.serve_forever()

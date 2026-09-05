#!/usr/bin/env python3
"""
FarsHub Panel — local preview server.

Serves web/ and fakes the /data endpoint so the panel can be checked without a
running tunnel. Development only; never deploy this.

    python web/devserver.py [--port 8770]
"""

import argparse
import json
import math
import os
import random
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)))
T0 = time.time()

PORTS = [
    ("443", "127.0.0.1:8443"),
    ("8080", "127.0.0.1:80"),
    ("2096", "10.0.0.5:2096"),
    ("51820", "127.0.0.1:51820"),
    ("9000-9010", "127.0.0.1:9000"),
]

EVENTS = [
    ("info", "control channel established successfully"),
    ("info", "connection pool warmed to 8 connections"),
    ("warn", "keepalive ping took 412ms"),
    ("info", "increasing pool size: 8 -> 12"),
    ("error", "failed to dial local service on 127.0.0.1:8443"),
    ("info", "channel signal received, initiating tunnel dialer"),
]


def snapshot(bare=False):
    """Plausible moving numbers so sparklines and rails have something to show.

    bare=True drops every optional field (host details, version, byte totals) so
    the panel's "service reports nothing" path can be exercised: rows should
    disappear rather than fill with em dashes.
    """
    t = time.time() - T0
    wave = (math.sin(t / 9) + 1) / 2
    tx = int(2.4e6 + wave * 9.5e6 + random.uniform(-4e5, 4e5))
    rx = int(1.1e6 + (1 - wave) * 6.2e6 + random.uniform(-3e5, 3e5))

    ports = []
    for i, (port, target) in enumerate(PORTS):
        share = 0.42 / (i + 1)
        ports.append({
            "port": port,
            "target": target,
            "connections": max(0, int(48 * share + random.uniform(-3, 3))),
            "upload": int(t * 9.1e5 * share),
            "download": int(t * 4.4e5 * share),
            "rate": int((tx + rx) * share),
        })

    return {
        "status": "connected",
        "role": "server",
        "transport": "tcpmux",
        "version": None if bare else "0.6.5",
        # مشخصات میزبان — پنل اینها را از server/host/system هم می‌خواند
        "server": None if bare else {
            "hostname": "fra-edge-01",
            "ip": "203.0.113.42",
            "location": "Frankfurt, DE",
            "os": "Debian GNU/Linux 12 (bookworm)",
            "kernel": "6.1.0-18-amd64",
            "arch": "x86_64",
            "cores": 4,
            "bind_addr": "0.0.0.0:3080",
            "boot_time": 1_284_000,
        },
        "tx_rate": tx,
        "rx_rate": rx,
        "latency": round(28 + wave * 22 + random.uniform(-4, 4), 1),
        "connections": sum(p["connections"] for p in ports),
        "goroutines": 180 + int(wave * 60),
        "uptime": int(t) + 96_400,
        "cpu": round(14 + wave * 26, 1),
        "memory_percent": round(58 + wave * 9, 1),
        "memory": None if bare else {"used": 4_912_345_088, "total": 8_337_244_160},
        "disk_percent": 81.4,
        "disk": None if bare else {"used": 34_882_670_592, "total": 42_949_672_960},
        "swap_percent": round(3 + wave * 2, 1),
        "ports": ports,
        "events": [
            {"time": time.strftime("%Y-%m-%dT%H:%M:%S"), "level": lvl, "message": msg}
            for lvl, msg in EVENTS
        ],
    }


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def do_GET(self):
        path, _, query = self.path.partition("?")
        if path in ("/data", "/stats"):
            # ?bare=1 → پاسخ حداقلی، برای تست حالت «سرویس چیزی نمی‌فرستد»
            body = json.dumps(snapshot(bare="bare=1" in query)).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def log_message(self, fmt, *args):
        if "/data" not in (args[0] if args else ""):
            super().log_message(fmt, *args)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8770)
    args = ap.parse_args()
    # 127.0.0.1 only — this server has no auth and serves synthetic data.
    print(f"FarsHub panel preview -> http://127.0.0.1:{args.port}/")
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()

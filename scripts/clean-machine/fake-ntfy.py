#!/usr/bin/env python3
"""A minimal ntfy server for the clean-machine matrix, run inside the guest on 127.0.0.1.

Just enough for the app: GET /v1/account answers 200, GET /<topics>/json streams (or polls) three fixed
messages per topic and then holds the stream open. It lets a cell give the app a server, a token and a
history without the tailnet dev server. Not a ntfy implementation.
"""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *_):
        pass

    def do_GET(self):
        path, _, query = self.path.partition("?")
        if path == "/v1/account":
            return self.reply(200, b'{"username":"clean-machine","role":"user"}')
        if not path.endswith("/json"):
            return self.reply(404, b'{"error":"not found"}')
        topics = path.strip("/").rsplit("/", 1)[0].split(",")
        poll = "poll=1" in query
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.end_headers()
        now = int(time.time()) - 3600
        for topic in topics:
            for n in range(1, 4):
                message = {
                    "id": f"seed{n:03d}{topic[:8]}"[:12].ljust(12, "x"),
                    "time": now + n,
                    "expires": now + 86400,
                    "event": "message",
                    "topic": topic,
                    "title": f"seed {n}",
                    "message": f"clean-machine seed message {n}",
                    "priority": 3,
                }
                self.wfile.write((json.dumps(message) + "\n").encode())
        self.wfile.flush()
        if poll:
            return
        try:
            while True:
                time.sleep(30)
                self.wfile.write((json.dumps({"event": "keepalive", "time": int(time.time())}) + "\n").encode())
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            return

    def reply(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18080
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()

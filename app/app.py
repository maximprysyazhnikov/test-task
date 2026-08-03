"""Tiny dependency-free HTTP service used by both Compose and Kubernetes."""

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class HealthHandler(BaseHTTPRequestHandler):
    """Serve a deterministic health response and reject unknown paths."""

    server_version = "winwin-health/1.0"

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if self.path.split("?", 1)[0] != "/healthz":
            self._write_json(404, {"status": "not_found"})
            return

        self._write_json(
            200,
            {
                "status": "ok",
                "service": "app",
                "env": os.getenv("ENV_NAME", "local"),
            },
        )

    def _write_json(self, status: int, payload: dict[str, str]) -> None:
        """Encode once so Content-Length always matches the response body."""
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        # Echo the proxy-provided ID so pass-through can be tested end to end.
        request_id = self.headers.get("X-Request-ID")
        if request_id:
            self.send_header("X-Request-ID", request_id)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt: str, *args: object) -> None:
        """Keep container logs useful while retaining the standard format."""
        super().log_message(fmt, *args)


if __name__ == "__main__":
    # Listen on all container interfaces; the app port is never published directly.
    ThreadingHTTPServer(("0.0.0.0", 8080), HealthHandler).serve_forever()

"""A health endpoint on port 8083.

Docker Compose and the architecture document both expect one. Without it, an orchestrator can only
tell that the process is running, and a poller whose Kafka producer died is still a running process.

The server is deliberately the standard library's. Adding a web framework to a service with one
route buys nothing and adds a dependency to audit.
"""

from __future__ import annotations

import json
import logging
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable

log = logging.getLogger(__name__)


class HealthServer:
    """Serves ``GET /health`` from a background daemon thread."""

    def __init__(self, port: int, state_provider: Callable[[], dict[str, Any]]) -> None:
        self._port = port
        self._state_provider = state_provider
        self._server: ThreadingHTTPServer | None = None
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        handler = _make_handler(self._state_provider)
        self._server = ThreadingHTTPServer(("0.0.0.0", self._port), handler)
        self._thread = threading.Thread(
            target=self._server.serve_forever, name="health", daemon=True
        )
        self._thread.start()
        log.info("Health endpoint listening", extra={"port": self._port})

    def stop(self) -> None:
        if self._server is not None:
            self._server.shutdown()
            self._server.server_close()
            self._server = None
        if self._thread is not None:
            self._thread.join(timeout=5)
            self._thread = None


def _make_handler(state_provider: Callable[[], dict[str, Any]]):

    class Handler(BaseHTTPRequestHandler):

        protocol_version = "HTTP/1.1"

        def do_GET(self) -> None:  # noqa: N802, the base class names it
            if self.path.split("?")[0] not in ("/health", "/healthz"):
                self.send_error(404)
                return
            state = state_provider()
            body = json.dumps(state, default=str).encode("utf-8")
            # A degraded poller is still answering, so it returns 200 with a status field rather
            # than a 503. Restarting a container that is publishing quotes slowly makes it publish
            # none at all for the length of the restart.
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt: str, *args: Any) -> None:
            # The default writes to stderr in a format nothing else in this service uses.
            log.debug("Health request", extra={"detail": fmt % args})

    return Handler

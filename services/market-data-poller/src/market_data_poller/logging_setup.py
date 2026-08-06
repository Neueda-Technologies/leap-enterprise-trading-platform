"""One JSON object per log line.

A poller writes a line every interval for as long as the platform is up. Grepping that by eye does
not scale, and the fields worth filtering on, the symbol and the request count, are the ones a
free-text message buries. Structured lines can be filtered with ``jq`` and shipped without a parser.
"""

from __future__ import annotations

import json
import logging
import sys
from datetime import datetime, timezone

#: Attributes the logging module puts on every record. Anything else was added by the caller
#: through ``extra=`` and belongs in the output.
_STANDARD_ATTRIBUTES = frozenset(
    {
        "args", "asctime", "created", "exc_info", "exc_text", "filename", "funcName",
        "levelname", "levelno", "lineno", "message", "module", "msecs", "msg", "name",
        "pathname", "process", "processName", "relativeCreated", "stack_info", "taskName",
        "thread", "threadName",
    }
)


class JsonFormatter(logging.Formatter):
    """Renders a record as a single-line JSON object."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(
                timespec="milliseconds"
            ).replace("+00:00", "Z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for key, value in record.__dict__.items():
            if key not in _STANDARD_ATTRIBUTES and not key.startswith("_"):
                payload[key] = value
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


def configure_logging(level: str = "INFO") -> None:
    """Replaces the root handlers with one JSON handler on stdout.

    Logs go to stdout, not to a file. A container writes to stdout and lets the platform decide
    where that goes; a container that manages its own log files has to manage their rotation too.
    """
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(getattr(logging, level.upper(), logging.INFO))

    # kafka-python logs every metadata refresh at INFO, which drowns the poller's own lines.
    logging.getLogger("kafka").setLevel(logging.WARNING)

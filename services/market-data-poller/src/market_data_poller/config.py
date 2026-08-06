"""Settings, read once from the environment at start-up.

Nothing in this package reads ``os.environ`` anywhere else. One place to look means one place to
change, and it makes every other module testable by constructing a ``Settings`` directly.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from typing import Mapping

log = logging.getLogger(__name__)

#: Fauxnance accepts at most 25 symbols in one batch call, and that call costs one quota unit.
MAX_BATCH_SIZE = 25

#: The floor on the poll interval. See the quota arithmetic in README.md. Below this the daily
#: quota cannot survive a working day, whatever the symbol count.
MINIMUM_POLL_INTERVAL_SECONDS = 15.0

DEFAULT_SYMBOLS = "AAPL,MSFT,GOOGL,AMZN,TSLA,NVDA,JPM,SPY"

DEFAULT_BASE_URL = "https://y4t9nq2bqf.execute-api.eu-west-2.amazonaws.com/v1"


class ConfigurationError(RuntimeError):
    """The process cannot start with the configuration it was given."""


@dataclass(frozen=True)
class Settings:
    """Everything the poller needs, resolved and validated."""

    base_url: str
    api_key: str
    symbols: tuple[str, ...]
    poll_interval_seconds: float
    bootstrap_servers: str
    topic: str
    request_timeout_seconds: float
    max_attempts: int
    backoff_initial_seconds: float
    backoff_max_seconds: float
    daily_request_budget: int
    health_port: int
    log_level: str

    @property
    def requests_per_poll(self) -> int:
        """One batch call per group of 25 symbols."""
        return (len(self.symbols) + MAX_BATCH_SIZE - 1) // MAX_BATCH_SIZE

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "Settings":
        source = os.environ if env is None else env

        api_key = source.get("FAUXNANCE_API_KEY", "").strip()
        if not api_key:
            raise ConfigurationError(
                "FAUXNANCE_API_KEY is not set. Every request would be rejected with 401."
            )

        symbols = parse_symbols(source.get("MARKET_DATA_SYMBOLS", DEFAULT_SYMBOLS))
        if not symbols:
            raise ConfigurationError("MARKET_DATA_SYMBOLS resolved to an empty list.")

        interval = _float(source, "POLL_INTERVAL_SECONDS", 30.0)
        if interval < MINIMUM_POLL_INTERVAL_SECONDS:
            log.warning(
                "POLL_INTERVAL_SECONDS raised to the floor",
                extra={
                    "requested": interval,
                    "applied": MINIMUM_POLL_INTERVAL_SECONDS,
                    "reason": "daily quota",
                },
            )
            interval = MINIMUM_POLL_INTERVAL_SECONDS

        return cls(
            base_url=source.get("FAUXNANCE_BASE_URL", DEFAULT_BASE_URL).rstrip("/"),
            api_key=api_key,
            symbols=symbols,
            poll_interval_seconds=interval,
            bootstrap_servers=source.get("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"),
            topic=source.get("MARKET_DATA_TOPIC", "market-data"),
            request_timeout_seconds=_float(source, "REQUEST_TIMEOUT_SECONDS", 5.0),
            max_attempts=_int(source, "MAX_ATTEMPTS", 3),
            backoff_initial_seconds=_float(source, "BACKOFF_INITIAL_SECONDS", 1.0),
            backoff_max_seconds=_float(source, "BACKOFF_MAX_SECONDS", 60.0),
            daily_request_budget=_int(source, "DAILY_REQUEST_BUDGET", 2000),
            health_port=_int(source, "HEALTH_PORT", 8083),
            log_level=source.get("LOG_LEVEL", "INFO").upper(),
        )


def parse_symbols(raw: str) -> tuple[str, ...]:
    """Split a comma-separated list, dropping blanks and duplicates but keeping the order.

    Order is kept so that the batches a team sees in the logs match the order they configured,
    which makes a missing symbol easy to spot.
    """
    seen: dict[str, None] = {}
    for part in raw.split(","):
        symbol = part.strip().upper()
        if symbol:
            seen.setdefault(symbol, None)
    return tuple(seen)


def _int(source: Mapping[str, str], name: str, default: int) -> int:
    raw = source.get(name)
    if raw is None or not raw.strip():
        return default
    try:
        return int(raw)
    except ValueError as exc:
        raise ConfigurationError(f"{name} must be an integer, got {raw!r}") from exc


def _float(source: Mapping[str, str], name: str, default: float) -> float:
    raw = source.get(name)
    if raw is None or not raw.strip():
        return default
    try:
        return float(raw)
    except ValueError as exc:
        raise ConfigurationError(f"{name} must be a number, got {raw!r}") from exc

"""Fakes for the two boundaries this service has: HTTP and Kafka.

Both are hand-written rather than mocked. The assertions are about how many requests were made and
what was published, and a hand-written fake that records those is easier to read than a mock with
five call assertions.
"""

from __future__ import annotations

from typing import Any, Sequence

from market_data_poller.config import Settings
from market_data_poller.fauxnance import BatchResult, Quote


class FakeResponse:
    """Enough of a ``requests.Response`` for the client under test."""

    def __init__(self, status_code: int = 200, payload: Any = None, malformed: bool = False):
        self.status_code = status_code
        self._payload = payload
        self._malformed = malformed

    def json(self) -> Any:
        if self._malformed:
            raise ValueError("not json")
        return self._payload


class FakeSession:
    """Returns queued responses and records the calls."""

    def __init__(self, responses: Sequence[Any] | None = None):
        self.headers: dict[str, str] = {}
        self.calls: list[dict[str, Any]] = []
        self._responses = list(responses or [])

    def get(self, url: str, params: dict[str, Any] | None = None, timeout: float | None = None):
        self.calls.append({"url": url, "params": params or {}, "timeout": timeout})
        if not self._responses:
            return FakeResponse(200, {"data": {"quotes": []}, "meta": {}})
        nxt = self._responses.pop(0)
        if isinstance(nxt, Exception):
            raise nxt
        return nxt


class FakeProducer:
    """Records every send. One entry per message, which is what the contract asks for."""

    def __init__(self, fail_for: set[str] | None = None):
        self.sent: list[tuple[str, bytes, bytes]] = []
        self.flushed = 0
        self.closed = False
        self._fail_for = fail_for or set()

    def send(self, topic: str, key: bytes, value: bytes) -> None:
        if key.decode("utf-8") in self._fail_for:
            raise RuntimeError("broker unreachable")
        self.sent.append((topic, key, value))

    def flush(self, timeout: float | None = None) -> None:
        self.flushed += 1

    def close(self, timeout: float | None = None) -> None:
        self.closed = True


class FakeClient:
    """A Fauxnance client that answers from a script."""

    def __init__(self, script: Sequence[Any] | None = None):
        self.calls: list[tuple[str, ...]] = []
        self._script = list(script or [])

    def batch_quotes(self, symbols: Sequence[str]) -> BatchResult:
        self.calls.append(tuple(symbols))
        if not self._script:
            return BatchResult(quotes=tuple(quote(s) for s in symbols), failed_symbols=())
        nxt = self._script.pop(0)
        if isinstance(nxt, Exception):
            raise nxt
        return nxt


class FakePublisher:
    def __init__(self, fail_for: set[str] | None = None):
        self.published: list[Quote] = []
        self.flushed = 0
        self._fail_for = fail_for or set()

    def publish(self, quote_to_publish: Quote, event_time: Any = None) -> None:
        if quote_to_publish.symbol in self._fail_for:
            raise RuntimeError("broker unreachable")
        self.published.append(quote_to_publish)

    def flush(self, timeout: float | None = None) -> None:
        self.flushed += 1


def quote(symbol: str = "AAPL", price: float = 232.71, stale: bool = False) -> Quote:
    return Quote(
        symbol=symbol,
        price=price,
        currency="USD",
        change=0.21,
        change_percent=0.09,
        previous_close=232.50,
        market_state="open",
        stale=stale,
        as_of="2026-09-28T09:14:58Z",
    )


def settings(**overrides: Any) -> Settings:
    base = {
        "base_url": "https://fauxnance.test/v1",
        "api_key": "test-key",
        "symbols": ("AAPL", "MSFT"),
        "poll_interval_seconds": 30.0,
        "bootstrap_servers": "localhost:9092",
        "topic": "market-data",
        "request_timeout_seconds": 5.0,
        "max_attempts": 3,
        "backoff_initial_seconds": 1.0,
        "backoff_max_seconds": 60.0,
        "daily_request_budget": 2000,
        "health_port": 8083,
        "log_level": "INFO",
    }
    base.update(overrides)
    return Settings(**base)

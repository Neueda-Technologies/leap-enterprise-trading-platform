"""Publishes quotes to the ``market-data`` topic.

One message per symbol, never one per batch. Batching the HTTP call is a quota optimisation.
Batching the Kafka message would put several symbols behind one key, which breaks per-symbol
ordering and stops a consumer from subscribing to the instruments it cares about.
"""

from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Any, Callable

from .fauxnance import Quote

log = logging.getLogger(__name__)

SOURCE = "market-poller"
EVENT_TYPE = "QUOTE"
SCHEMA_VERSION = 1


def build_envelope(quote: Quote, event_time: datetime | None = None) -> dict[str, Any]:
    """Builds the contracted envelope and payload for one quote.

    ``eventTime`` is when this process published. ``quoteAsOf`` is when Fauxnance observed the
    price. They differ, because Fauxnance serves delayed quotes, and a consumer that acts on
    ``eventTime`` is acting on a price older than it thinks.
    """
    published_at = event_time or datetime.now(tz=timezone.utc)
    return {
        "eventId": str(uuid.uuid4()),
        "eventType": EVENT_TYPE,
        "eventTime": _rfc3339(published_at),
        "source": SOURCE,
        "schemaVersion": SCHEMA_VERSION,
        "payload": {
            "symbol": quote.symbol,
            "price": quote.price,
            "currency": quote.currency,
            "change": quote.change,
            "changePercent": quote.change_percent,
            "previousClose": quote.previous_close,
            "marketState": quote.market_state,
            "stale": quote.stale,
            "quoteAsOf": quote.as_of,
        },
    }


class QuotePublisher:
    """Wraps a Kafka producer. The producer is injected so that tests never need a broker."""

    def __init__(self, topic: str, producer: Any) -> None:
        self._topic = topic
        self._producer = producer

    @classmethod
    def create(cls, bootstrap_servers: str, topic: str) -> "QuotePublisher":
        """Builds a producer with the platform's delivery settings.

        ``kafka`` is imported here rather than at module scope so that the unit tests can exercise
        every other line in this file without the library installed.
        """
        from kafka import KafkaProducer  # noqa: PLC0415, imported late on purpose

        producer = KafkaProducer(
            bootstrap_servers=[server.strip() for server in bootstrap_servers.split(",")],
            # acks=all and idempotence are what the topic contract asks producers for. They remove
            # duplicates caused by a producer retry. They do not remove duplicates caused by this
            # process restarting mid-poll, and nothing here pretends otherwise.
            acks="all",
            enable_idempotence=True,
            retries=10,
            max_in_flight_requests_per_connection=5,
            linger_ms=20,
        )
        return cls(topic=topic, producer=producer)

    def publish(self, quote: Quote, event_time: datetime | None = None) -> None:
        """Sends one quote. The key is the symbol, so a symbol's quotes stay ordered."""
        envelope = build_envelope(quote, event_time)
        self._producer.send(
            self._topic,
            key=quote.symbol.encode("utf-8"),
            value=json.dumps(envelope).encode("utf-8"),
        )
        log.debug("Published a quote", extra={"symbol": quote.symbol, "topic": self._topic})

    def flush(self, timeout: float | None = None) -> None:
        flush: Callable[..., Any] | None = getattr(self._producer, "flush", None)
        if flush is not None:
            flush(timeout)

    def close(self, timeout: float | None = 10.0) -> None:
        close: Callable[..., Any] | None = getattr(self._producer, "close", None)
        if close is not None:
            close(timeout)


def _rfc3339(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

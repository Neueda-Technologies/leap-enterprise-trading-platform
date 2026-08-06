from __future__ import annotations

import json
from datetime import datetime, timezone

from conftest import FakeProducer, quote

from market_data_poller.publisher import QuotePublisher, build_envelope

EVENT_TIME = datetime(2026, 9, 28, 9, 15, 0, tzinfo=timezone.utc)


def test_the_envelope_carries_exactly_the_contracted_fields():
    envelope = build_envelope(quote(), EVENT_TIME)

    assert set(envelope) == {
        "eventId", "eventType", "eventTime", "source", "schemaVersion", "payload"
    }
    assert set(envelope["payload"]) == {
        "symbol", "price", "currency", "change", "changePercent", "previousClose",
        "marketState", "stale", "quoteAsOf",
    }


def test_the_envelope_identifies_the_producer_and_the_schema():
    envelope = build_envelope(quote(), EVENT_TIME)

    assert envelope["eventType"] == "QUOTE"
    assert envelope["source"] == "market-poller"
    assert envelope["schemaVersion"] == 1
    assert envelope["eventTime"] == "2026-09-28T09:15:00Z"


def test_event_time_and_quote_as_of_are_different_instants():
    envelope = build_envelope(quote(), EVENT_TIME)

    assert envelope["eventTime"] == "2026-09-28T09:15:00Z"
    assert envelope["payload"]["quoteAsOf"] == "2026-09-28T09:14:58Z"


def test_market_state_is_passed_through_untouched():
    from market_data_poller.fauxnance import Quote

    closed = Quote("SPY", 601.2, "USD", None, None, None, "closed", False, None)

    assert build_envelope(closed, EVENT_TIME)["payload"]["marketState"] == "closed"


def test_every_event_gets_its_own_identifier():
    first = build_envelope(quote(), EVENT_TIME)["eventId"]
    second = build_envelope(quote(), EVENT_TIME)["eventId"]

    assert first != second


def test_one_message_per_symbol_keyed_by_symbol():
    producer = FakeProducer()
    publisher = QuotePublisher("market-data", producer)

    publisher.publish(quote("AAPL"), EVENT_TIME)
    publisher.publish(quote("MSFT"), EVENT_TIME)

    assert [key for _, key, _ in producer.sent] == [b"AAPL", b"MSFT"]
    assert {topic for topic, _, _ in producer.sent} == {"market-data"}


def test_the_value_is_utf_8_json():
    producer = FakeProducer()
    publisher = QuotePublisher("market-data", producer)

    publisher.publish(quote("AAPL"), EVENT_TIME)

    _, _, value = producer.sent[0]
    payload = json.loads(value.decode("utf-8"))["payload"]
    assert payload["symbol"] == "AAPL"
    assert payload["price"] == 232.71


def test_close_and_flush_reach_the_producer():
    producer = FakeProducer()
    publisher = QuotePublisher("market-data", producer)

    publisher.flush(1.0)
    publisher.close(1.0)

    assert producer.flushed == 1
    assert producer.closed is True

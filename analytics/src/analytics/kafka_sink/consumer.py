"""Consumes `trade-events` and appends fills, rejects and cancels to
`fact_trades`.

`process_message` is the whole of the business logic and takes no Kafka
object: it is a DuckDB connection and a parsed envelope in, a `ProcessResult`
out. `run_consumer` is the thin wrapper that owns the real `KafkaConsumer`
and calls it in a loop. That split is what lets pytest exercise the dedupe
and load logic with no broker running, per the "no network in tests" rule.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass

import duckdb
import pandas as pd

from analytics.config import KafkaSettings, Settings
from analytics.db.warehouse import connect
from analytics.etl.load import load_fact_trades, load_quarantine
from analytics.etl.transform import compute_trade_value
from analytics.etl.validate import validate_trades
from analytics.timeutil import utcnow

logger = logging.getLogger(__name__)

# trade-events carries only terminal outcomes (docs/contracts/kafka-topics.md).
# ORDER_PLACED lives on the `orders` topic, which this sink does not consume:
# a NEW order has no fill, reject or cancel outcome yet, so there is nothing
# for fact_trades to record until one of these three arrives.
_HANDLED_EVENT_TYPES = frozenset({"ORDER_FILLED", "ORDER_REJECTED", "ORDER_CANCELLED"})


@dataclass(frozen=True)
class ProcessResult:
    status: str  # "loaded", "duplicate", "quarantined", "ignored"
    reason: str | None = None


def _already_processed(conn: duckdb.DuckDBPyConnection, event_id: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM kafka_processed_events WHERE event_id = ?", [event_id]
    ).fetchone()
    return row is not None


def _mark_processed(conn: duckdb.DuckDBPyConnection, event_id: str, topic: str) -> None:
    conn.execute(
        "INSERT INTO kafka_processed_events (event_id, topic, processed_at) "
        "VALUES (?, ?, ?) ON CONFLICT (event_id) DO NOTHING",
        [event_id, topic, utcnow()],
    )


def _envelope_to_trade_row(envelope: dict) -> pd.DataFrame:
    """Shape a `trade-events` envelope into the same row shape
    `analytics.etl.transform.transform_trades` produces, so it can go
    through the same validation and the same upsert as the batch path.

    `created_at` is set to the event's `executedOn`, not the order's
    original `createdOn`, because trade-events does not carry the latter.
    This is a deliberate, documented gap: the next batch run re-extracts the
    order from Postgres and overwrites this row with the true
    `orders.created_on`, which is what "reconcile against the batch load"
    means in practice for this column. Until that run, a streamed row's
    `created_at` is a close approximation, not the authoritative value.
    """
    payload = envelope["payload"]
    status = payload["status"]
    quantity = payload["quantity"]
    price = payload["price"]
    executed_price = payload.get("executedPrice")
    executed_on = pd.to_datetime(payload["executedOn"])

    trade_value = compute_trade_value(quantity, price, executed_price, status)

    return pd.DataFrame(
        [
            {
                "source_order_id": str(payload["orderId"]),
                "source_account_id": int(payload["accountId"]),
                "symbol": payload["symbol"],
                "side": payload["side"],
                "quantity": quantity,
                "price": float(price),
                "status": status,
                "executed_price": executed_price,
                "trade_value": trade_value,
                "created_at": executed_on,
                "date_key": int(executed_on.strftime("%Y%m%d")),
            }
        ]
    )


def process_message(conn: duckdb.DuckDBPyConnection, raw_value: bytes | str) -> ProcessResult:
    """Process one Kafka message value. Never raises for a bad message: a
    malformed payload is a `ProcessResult(status="quarantined")`, not an
    exception that would stall the partition.
    """
    try:
        envelope = json.loads(raw_value)
    except (json.JSONDecodeError, TypeError) as exc:
        logger.error("Malformed trade-events message, sending to DLQ: %s", exc)
        return ProcessResult(status="quarantined", reason=f"malformed JSON: {exc}")

    event_id = envelope.get("eventId")
    event_type = envelope.get("eventType")

    if not event_id:
        return ProcessResult(status="quarantined", reason="missing eventId")

    if _already_processed(conn, event_id):
        return ProcessResult(status="duplicate")

    if event_type not in _HANDLED_EVENT_TYPES:
        # Not an error: this sink only cares about terminal trade outcomes.
        _mark_processed(conn, event_id, topic="trade-events")
        return ProcessResult(status="ignored", reason=f"eventType {event_type} not handled")

    try:
        row = _envelope_to_trade_row(envelope)
    except (KeyError, TypeError, ValueError) as exc:
        logger.error("Invalid trade-events payload, sending to DLQ: %s", exc)
        return ProcessResult(status="quarantined", reason=f"invalid payload: {exc}")

    dim_account = conn.execute(
        "SELECT account_key, source_id, is_current FROM dim_account"
    ).df()
    dim_instrument = conn.execute("SELECT instrument_key, symbol FROM dim_instrument").df()
    dim_date = conn.execute("SELECT date_key FROM dim_date").df()

    result = validate_trades(row, dim_account, dim_instrument, dim_date)

    conn.execute("BEGIN TRANSACTION")
    try:
        if not result.valid.empty:
            load_fact_trades(conn, result.valid)
        if not result.quarantined.empty:
            load_quarantine(conn, result.quarantined, stage="kafka_sink")
        _mark_processed(conn, event_id, topic="trade-events")
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise

    if not result.quarantined.empty:
        return ProcessResult(status="quarantined", reason=result.quarantined.iloc[0]["reason"])
    return ProcessResult(status="loaded")


def run_consumer(settings: Settings, max_messages: int | None = None) -> None:
    """Owns the real `KafkaConsumer` and the DuckDB connection. Runs until
    `max_messages` have been handled, or forever if `max_messages` is None.
    """
    from kafka import KafkaConsumer  # imported lazily: not needed by tests

    kafka_settings: KafkaSettings = settings.kafka
    conn = connect(settings.warehouse.path)
    consumer = KafkaConsumer(
        kafka_settings.trade_events_topic,
        bootstrap_servers=kafka_settings.bootstrap_servers,
        group_id=kafka_settings.consumer_group,
        enable_auto_commit=False,
        auto_offset_reset="earliest",
        value_deserializer=lambda v: v,
    )

    processed = 0
    try:
        for message in consumer:
            result = process_message(conn, message.value)
            logger.info(
                "offset=%d partition=%d status=%s reason=%s",
                message.offset,
                message.partition,
                result.status,
                result.reason,
            )
            # Commit after processing, never before: a crash mid-process
            # must reprocess the message, not lose it. See docs/contracts/kafka-topics.md,
            # "Consumers".
            consumer.commit()
            processed += 1
            if max_messages is not None and processed >= max_messages:
                break
    finally:
        consumer.close()
        conn.close()

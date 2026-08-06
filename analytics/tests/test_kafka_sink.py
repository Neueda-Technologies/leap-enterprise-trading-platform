from __future__ import annotations

import json

from analytics.kafka_sink.consumer import process_message


def _order_filled_envelope(event_id: str, order_id: str, **overrides) -> str:
    payload = {
        "orderId": order_id,
        "accountId": 1,
        "symbol": "AAPL",
        "side": "BUY",
        "quantity": 100,
        "price": 233.00,
        "executedPrice": 232.71,
        "status": "FILLED",
        "reason": None,
        "cashDelta": -23271.00,
        "positionQuantityAfter": 300,
        "averageCostAfter": 229.83,
        "executedOn": "2026-09-28T09:14:24Z",
        **overrides,
    }
    envelope = {
        "eventId": event_id,
        "eventType": "ORDER_FILLED",
        "eventTime": "2026-09-28T09:14:24Z",
        "source": "trade-executor",
        "schemaVersion": 1,
        "payload": payload,
    }
    return json.dumps(envelope)


class TestProcessMessage:
    def test_valid_fill_is_loaded_into_fact_trades(self, seeded_warehouse):
        message = _order_filled_envelope("evt-1", "order-1")
        result = process_message(seeded_warehouse, message)
        assert result.status == "loaded"
        row = seeded_warehouse.execute(
            "SELECT f.status, f.executed_price, f.side, i.symbol "
            "FROM fact_trades f JOIN dim_instrument i ON i.instrument_key = f.instrument_key "
            "WHERE f.source_order_id = ?",
            ["order-1"],
        ).fetchone()
        assert row[0] == "FILLED"
        assert float(row[1]) == 232.71
        assert row[2] == "BUY"
        assert row[3] == "AAPL"

    def test_duplicate_event_id_is_not_reloaded(self, seeded_warehouse):
        message = _order_filled_envelope("evt-2", "order-2")
        first = process_message(seeded_warehouse, message)
        second = process_message(seeded_warehouse, message)

        assert first.status == "loaded"
        assert second.status == "duplicate"
        count = seeded_warehouse.execute(
            "SELECT COUNT(*) FROM fact_trades WHERE source_order_id = ?", ["order-2"]
        ).fetchone()[0]
        assert count == 1

    def test_two_different_event_ids_for_the_same_order_update_one_row(self, seeded_warehouse):
        """A retried publish with a new eventId but the same orderId (for
        example a reconciliation replay) must still land on one fact row,
        because the upsert key is source_order_id, not eventId.
        """
        process_message(seeded_warehouse, _order_filled_envelope("evt-3a", "order-3"))
        process_message(
            seeded_warehouse,
            _order_filled_envelope("evt-3b", "order-3", executedPrice=240.00),
        )
        rows = seeded_warehouse.execute(
            "SELECT COUNT(*), MAX(executed_price) FROM fact_trades WHERE source_order_id = ?",
            ["order-3"],
        ).fetchone()
        assert rows[0] == 1
        assert float(rows[1]) == 240.00

    def test_malformed_json_is_quarantined_not_raised(self, seeded_warehouse):
        result = process_message(seeded_warehouse, b"{not valid json")
        assert result.status == "quarantined"

    def test_missing_event_id_is_quarantined(self, seeded_warehouse):
        envelope = json.dumps({"eventType": "ORDER_FILLED", "payload": {}})
        result = process_message(seeded_warehouse, envelope)
        assert result.status == "quarantined"

    def test_unhandled_event_type_is_ignored(self, seeded_warehouse):
        envelope = json.dumps(
            {"eventId": "evt-quote", "eventType": "QUOTE", "payload": {"symbol": "AAPL"}}
        )
        result = process_message(seeded_warehouse, envelope)
        assert result.status == "ignored"

    def test_unresolvable_account_is_quarantined_not_loaded(self, seeded_warehouse):
        message = _order_filled_envelope("evt-4", "order-4", accountId=999)
        result = process_message(seeded_warehouse, message)
        assert result.status == "quarantined"
        count = seeded_warehouse.execute(
            "SELECT COUNT(*) FROM fact_trades WHERE source_order_id = ?", ["order-4"]
        ).fetchone()[0]
        assert count == 0

    def test_rejected_order_is_loaded_with_no_executed_price(self, seeded_warehouse):
        message = _order_filled_envelope(
            "evt-5",
            "order-5",
            status="REJECTED",
            executedPrice=None,
        )
        # ORDER_REJECTED events reuse the same payload shape in practice; this
        # test drives the eventType directly since REJECTED implies eventType
        # ORDER_REJECTED per docs/contracts/kafka-topics.md.
        envelope = json.loads(message)
        envelope["eventType"] = "ORDER_REJECTED"
        result = process_message(seeded_warehouse, json.dumps(envelope))
        assert result.status == "loaded"
        row = seeded_warehouse.execute(
            "SELECT status, executed_price, trade_value FROM fact_trades WHERE source_order_id = ?",
            ["order-5"],
        ).fetchone()
        assert row[0] == "REJECTED"
        assert row[1] is None
        assert float(row[2]) == 233.00 * 100

from __future__ import annotations

import pandas as pd
import pytest

from analytics.etl.transform import transform_trades
from analytics.etl.validate import check_candle_reasonableness, validate_trades
from factories import make_orders_raw


@pytest.fixture()
def dims():
    dim_account = pd.DataFrame(
        {
            "account_key": [101, 102],
            "source_id": [1, 2],
            "is_current": [True, True],
        }
    )
    dim_instrument = pd.DataFrame(
        {
            "instrument_key": [201, 202],
            "symbol": ["AAPL", "MSFT"],
        }
    )
    dim_date = pd.DataFrame({"date_key": [20260115, 20260116]})
    return dim_account, dim_instrument, dim_date


class TestValidateTrades:
    def test_valid_row_passes_and_resolves_keys(self, dims):
        dim_account, dim_instrument, dim_date = dims
        trades = transform_trades(
            make_orders_raw([{"account_id": 1, "symbol": "AAPL", "quantity": 10, "price": 100.0}])
        )
        result = validate_trades(trades, dim_account, dim_instrument, dim_date)
        assert result.valid_count == 1
        assert result.quarantined_count == 0
        assert result.valid.iloc[0]["account_key"] == 101
        assert result.valid.iloc[0]["instrument_key"] == 201

    def test_non_positive_quantity_is_quarantined(self, dims):
        dim_account, dim_instrument, dim_date = dims
        trades = transform_trades(make_orders_raw([{"quantity": 0}]))
        result = validate_trades(trades, dim_account, dim_instrument, dim_date)
        assert result.valid_count == 0
        assert "quantity" in result.quarantined.iloc[0]["reason"]

    def test_non_positive_price_is_quarantined(self, dims):
        dim_account, dim_instrument, dim_date = dims
        trades = transform_trades(make_orders_raw([{"price": -5.0}]))
        result = validate_trades(trades, dim_account, dim_instrument, dim_date)
        assert result.valid_count == 0
        assert "price" in result.quarantined.iloc[0]["reason"]

    def test_invalid_side_is_quarantined(self, dims):
        dim_account, dim_instrument, dim_date = dims
        trades = transform_trades(make_orders_raw([{"side": "HOLD"}]))
        result = validate_trades(trades, dim_account, dim_instrument, dim_date)
        assert result.valid_count == 0
        assert "side" in result.quarantined.iloc[0]["reason"]

    def test_invalid_status_is_quarantined(self, dims):
        dim_account, dim_instrument, dim_date = dims
        trades = transform_trades(make_orders_raw([{"status": "PENDING_REVIEW"}]))
        result = validate_trades(trades, dim_account, dim_instrument, dim_date)
        assert result.valid_count == 0
        assert "status" in result.quarantined.iloc[0]["reason"]

    def test_unresolvable_account_is_quarantined(self, dims):
        dim_account, dim_instrument, dim_date = dims
        trades = transform_trades(make_orders_raw([{"account_id": 999}]))
        result = validate_trades(trades, dim_account, dim_instrument, dim_date)
        assert result.valid_count == 0
        assert "dim_account" in result.quarantined.iloc[0]["reason"]

    def test_unresolvable_instrument_is_quarantined(self, dims):
        dim_account, dim_instrument, dim_date = dims
        trades = transform_trades(make_orders_raw([{"symbol": "ZZZZ"}]))
        result = validate_trades(trades, dim_account, dim_instrument, dim_date)
        assert result.valid_count == 0
        assert "dim_instrument" in result.quarantined.iloc[0]["reason"]

    def test_tampered_trade_value_is_quarantined(self, dims):
        dim_account, dim_instrument, dim_date = dims
        trades = transform_trades(make_orders_raw([{"quantity": 10, "price": 100.0}]))
        trades.loc[0, "trade_value"] = 1.0  # corrupt it after transform computed it correctly
        result = validate_trades(trades, dim_account, dim_instrument, dim_date)
        assert result.valid_count == 0
        assert "trade_value" in result.quarantined.iloc[0]["reason"]

    def test_duplicate_source_order_id_in_batch_keeps_latest(self, dims):
        dim_account, dim_instrument, dim_date = dims
        raw = make_orders_raw([{"status": "NEW"}, {"status": "FILLED"}])
        raw["id"] = "00000000-0000-0000-0000-000000000099"  # force the same order id twice
        trades = transform_trades(raw)
        result = validate_trades(trades, dim_account, dim_instrument, dim_date)
        assert result.valid_count == 1
        assert result.valid.iloc[0]["status"] == "FILLED"
        assert result.quarantined_count == 1

    def test_empty_input_returns_empty_result(self, dims):
        dim_account, dim_instrument, dim_date = dims
        empty = transform_trades(pd.DataFrame(columns=[
            "id", "account_id", "symbol", "side", "quantity", "price", "status",
            "executed_price", "executed_on", "reject_reason", "created_on",
        ]))
        result = validate_trades(empty, dim_account, dim_instrument, dim_date)
        assert result.valid_count == 0
        assert result.quarantined_count == 0

    def test_row_counts_and_nulls_report(self, dims):
        dim_account, dim_instrument, dim_date = dims
        trades = transform_trades(
            make_orders_raw([{"account_id": 1, "symbol": "AAPL"}, {"account_id": 2, "symbol": "MSFT"}])
        )
        result = validate_trades(trades, dim_account, dim_instrument, dim_date)
        assert result.valid_count == 2
        assert result.valid["account_key"].isna().sum() == 0


class TestCandleReasonableness:
    def test_fill_within_range_has_no_anomaly(self, dims):
        dim_account, dim_instrument, dim_date = dims
        trades = transform_trades(
            make_orders_raw([{"status": "FILLED", "executed_price": 101.0}])
        )
        candles = pd.DataFrame(
            [{"symbol": "AAPL", "trade_date": trades.iloc[0]["created_at"].date(),
              "low": 99.0, "high": 103.0}]
        )
        anomalies = check_candle_reasonableness(trades, candles)
        assert anomalies.empty

    def test_fill_outside_range_is_an_anomaly(self, dims):
        dim_account, dim_instrument, dim_date = dims
        trades = transform_trades(
            make_orders_raw([{"status": "FILLED", "executed_price": 500.0}])
        )
        candles = pd.DataFrame(
            [{"symbol": "AAPL", "trade_date": trades.iloc[0]["created_at"].date(),
              "low": 99.0, "high": 103.0}]
        )
        anomalies = check_candle_reasonableness(trades, candles)
        assert len(anomalies) == 1

    def test_no_candles_means_no_anomalies_not_an_error(self):
        trades = transform_trades(make_orders_raw([{"status": "FILLED"}]))
        anomalies = check_candle_reasonableness(trades, pd.DataFrame())
        assert anomalies.empty

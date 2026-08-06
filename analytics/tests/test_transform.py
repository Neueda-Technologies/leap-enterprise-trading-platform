from __future__ import annotations

from datetime import date

import numpy as np
import pandas as pd
import pytest

from analytics.etl.transform import (
    compute_trade_value,
    derive_exchange,
    transform_accounts,
    transform_dates,
    transform_instruments,
    transform_trades,
)
from factories import make_orders_raw


class TestDeriveExchange:
    def test_plain_ticker_is_us(self):
        assert derive_exchange("AAPL") == "US"

    def test_ns_suffix_is_nse(self):
        assert derive_exchange("INFY.NS") == "NSE"

    def test_bo_suffix_is_bse(self):
        assert derive_exchange("TATASTEEL.BO") == "BSE"

    def test_fx_prefix_is_fx(self):
        assert derive_exchange("FX:EURUSD") == "FX"

    def test_crypto_prefix_is_crypto(self):
        assert derive_exchange("X:BTC-USD") == "CRYPTO"


class TestTransformInstruments:
    def test_adds_exchange_column(self, seed_instruments_raw):
        out = transform_instruments(seed_instruments_raw)
        assert "exchange" in out.columns
        assert set(out.loc[out["symbol"] != "SPY", "exchange"]) == {"US"}

    def test_empty_input_returns_empty_with_columns(self):
        out = transform_instruments(pd.DataFrame(columns=["symbol", "name", "asset_class", "currency", "tradable"]))
        assert out.empty
        assert "exchange" in out.columns


class TestTransformAccounts:
    def test_stamps_effective_date(self, seed_accounts_raw):
        out = transform_accounts(seed_accounts_raw, date(2026, 1, 1))
        assert (out["effective_date"] == date(2026, 1, 1)).all()
        assert len(out) == len(seed_accounts_raw)


class TestTransformDates:
    def test_generates_one_row_per_day(self):
        out = transform_dates(date(2026, 1, 1), date(2026, 1, 5))
        assert len(out) == 5
        assert out["date_key"].tolist() == [20260101, 20260102, 20260103, 20260104, 20260105]

    def test_day_name_and_weekday_flag(self):
        # 1 Jan 2026 is a Thursday.
        out = transform_dates(date(2026, 1, 1), date(2026, 1, 4))
        row = out.iloc[0]
        assert row["day_name"] == "Thursday"
        assert bool(row["is_weekday"]) is True
        saturday = out.iloc[2]
        assert saturday["day_name"] == "Saturday"
        assert bool(saturday["is_weekday"]) is False

    def test_quarter_computed_correctly(self):
        out = transform_dates(date(2026, 3, 31), date(2026, 4, 1))
        assert out.iloc[0]["quarter"] == 1
        assert out.iloc[1]["quarter"] == 2

    def test_rejects_inverted_range(self):
        with pytest.raises(ValueError):
            transform_dates(date(2026, 1, 5), date(2026, 1, 1))


class TestComputeTradeValue:
    def test_filled_uses_executed_price(self):
        assert compute_trade_value(10, 100.0, 105.0, "FILLED") == 1050.0

    def test_unfilled_uses_limit_price(self):
        assert compute_trade_value(10, 100.0, None, "NEW") == 1000.0

    def test_rejected_uses_limit_price_even_with_nan_executed(self):
        assert compute_trade_value(5, 50.0, np.nan, "REJECTED") == 250.0


class TestTransformTrades:
    def test_computes_trade_value_and_date_key(self):
        raw = make_orders_raw(
            [{"quantity": 10, "price": 100.0, "executed_price": 105.0, "status": "FILLED"}]
        )
        out = transform_trades(raw)
        assert out.iloc[0]["trade_value"] == 1050.0
        assert out.iloc[0]["date_key"] == 20260115

    def test_new_order_has_no_executed_price_but_still_gets_a_trade_value(self):
        raw = make_orders_raw(
            [{"quantity": 4, "price": 20.0, "executed_price": None, "status": "NEW"}]
        )
        out = transform_trades(raw)
        assert out.iloc[0]["trade_value"] == 80.0

    def test_malformed_price_raises(self):
        """A malformed-input case, per the week-05 acceptance criterion that
        pytest covers at least one. A non-numeric price cannot be cast, and
        transform must fail loudly rather than silently produce NaN.
        """
        raw = make_orders_raw([{"price": "not-a-number"}])
        with pytest.raises(ValueError):
            transform_trades(raw)

    def test_empty_input_returns_empty_with_expected_columns(self):
        out = transform_trades(pd.DataFrame(columns=[
            "id", "account_id", "symbol", "side", "quantity", "price", "status",
            "executed_price", "executed_on", "reject_reason", "created_on",
        ]))
        assert out.empty
        assert "trade_value" in out.columns
        assert "date_key" in out.columns

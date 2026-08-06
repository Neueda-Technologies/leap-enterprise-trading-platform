from __future__ import annotations

from datetime import date

import pandas as pd

from analytics.etl.load import load_dim_account, load_dim_date, load_dim_instrument, load_fact_trades
from analytics.etl.transform import transform_accounts, transform_dates, transform_instruments, transform_trades
from analytics.etl.validate import validate_trades
from conftest import TEST_EFFECTIVE_DATE
from factories import make_orders_raw


class TestDimDateIdempotency:
    def test_reloading_the_same_range_does_not_duplicate_rows(self, warehouse_conn):
        dates = transform_dates(date(2026, 1, 1), date(2026, 1, 10))
        first = load_dim_date(warehouse_conn, dates)
        second = load_dim_date(warehouse_conn, dates)
        assert first == 10
        assert second == 0
        count = warehouse_conn.execute("SELECT COUNT(*) FROM dim_date").fetchone()[0]
        assert count == 10


class TestDimInstrumentIdempotency:
    def test_reloading_unchanged_instruments_keeps_the_same_keys(self, warehouse_conn, seed_instruments_raw):
        instruments = transform_instruments(seed_instruments_raw)
        load_dim_instrument(warehouse_conn, instruments)
        before = warehouse_conn.execute(
            "SELECT symbol, instrument_key FROM dim_instrument ORDER BY symbol"
        ).df()

        load_dim_instrument(warehouse_conn, instruments)
        after = warehouse_conn.execute(
            "SELECT symbol, instrument_key FROM dim_instrument ORDER BY symbol"
        ).df()

        pd.testing.assert_frame_equal(before, after)
        count = warehouse_conn.execute("SELECT COUNT(*) FROM dim_instrument").fetchone()[0]
        assert count == len(seed_instruments_raw)

    def test_type_1_overwrite_changes_name_in_place(self, warehouse_conn, seed_instruments_raw):
        instruments = transform_instruments(seed_instruments_raw)
        load_dim_instrument(warehouse_conn, instruments)
        key_before = warehouse_conn.execute(
            "SELECT instrument_key FROM dim_instrument WHERE symbol = 'AAPL'"
        ).fetchone()[0]

        renamed = instruments.copy()
        renamed.loc[renamed["symbol"] == "AAPL", "name"] = "Apple Incorporated"
        load_dim_instrument(warehouse_conn, renamed)

        row = warehouse_conn.execute(
            "SELECT instrument_key, name FROM dim_instrument WHERE symbol = 'AAPL'"
        ).fetchone()
        assert row[0] == key_before
        assert row[1] == "Apple Incorporated"
        assert warehouse_conn.execute(
            "SELECT COUNT(*) FROM dim_instrument WHERE symbol = 'AAPL'"
        ).fetchone()[0] == 1


class TestDimAccountSCD2:
    def test_new_account_gets_one_current_row(self, warehouse_conn, seed_accounts_raw):
        accounts = transform_accounts(seed_accounts_raw, TEST_EFFECTIVE_DATE)
        new_accounts, changed = load_dim_account(warehouse_conn, accounts, TEST_EFFECTIVE_DATE)
        assert new_accounts == len(seed_accounts_raw)
        assert changed == 0
        current_count = warehouse_conn.execute(
            "SELECT COUNT(*) FROM dim_account WHERE is_current"
        ).fetchone()[0]
        assert current_count == len(seed_accounts_raw)

    def test_unchanged_reload_is_a_no_op(self, warehouse_conn, seed_accounts_raw):
        accounts = transform_accounts(seed_accounts_raw, TEST_EFFECTIVE_DATE)
        load_dim_account(warehouse_conn, accounts, TEST_EFFECTIVE_DATE)
        total_before = warehouse_conn.execute("SELECT COUNT(*) FROM dim_account").fetchone()[0]

        new_accounts, changed = load_dim_account(warehouse_conn, accounts, date(2026, 2, 1))
        total_after = warehouse_conn.execute("SELECT COUNT(*) FROM dim_account").fetchone()[0]

        assert new_accounts == 0
        assert changed == 0
        assert total_before == total_after

    def test_status_change_closes_old_version_and_opens_a_new_one(self, warehouse_conn, seed_accounts_raw):
        accounts = transform_accounts(seed_accounts_raw, TEST_EFFECTIVE_DATE)
        load_dim_account(warehouse_conn, accounts, TEST_EFFECTIVE_DATE)

        suspended = seed_accounts_raw.copy()
        suspended.loc[suspended["source_id"] == 1, "status"] = "SUSPENDED"
        candidate = transform_accounts(suspended, date(2026, 2, 1))
        new_accounts, changed = load_dim_account(warehouse_conn, candidate, date(2026, 2, 1))

        assert new_accounts == 0
        assert changed == 1

        versions = warehouse_conn.execute(
            "SELECT status, is_current, end_date FROM dim_account "
            "WHERE account_id = ? ORDER BY effective_date",
            [seed_accounts_raw.loc[seed_accounts_raw["source_id"] == 1, "account_id"].iloc[0]],
        ).df()
        assert len(versions) == 2
        assert versions.iloc[0]["status"] == "ACTIVE"
        assert versions.iloc[0]["is_current"] == False  # noqa: E712
        assert versions.iloc[0]["end_date"] is not None
        assert versions.iloc[1]["status"] == "SUSPENDED"
        assert versions.iloc[1]["is_current"] == True  # noqa: E712

    def test_reapplying_the_scd2_load_twice_does_not_open_a_third_version(
        self, warehouse_conn, seed_accounts_raw
    ):
        accounts = transform_accounts(seed_accounts_raw, TEST_EFFECTIVE_DATE)
        load_dim_account(warehouse_conn, accounts, TEST_EFFECTIVE_DATE)

        suspended = seed_accounts_raw.copy()
        suspended.loc[suspended["source_id"] == 1, "status"] = "SUSPENDED"
        candidate = transform_accounts(suspended, date(2026, 2, 1))
        load_dim_account(warehouse_conn, candidate, date(2026, 2, 1))
        load_dim_account(warehouse_conn, candidate, date(2026, 2, 1))  # re-run the same load

        version_count = warehouse_conn.execute(
            "SELECT COUNT(*) FROM dim_account WHERE account_id = ?",
            [seed_accounts_raw.loc[seed_accounts_raw["source_id"] == 1, "account_id"].iloc[0]],
        ).fetchone()[0]
        assert version_count == 2


class TestFactTradesIdempotency:
    def test_reloading_the_same_batch_does_not_duplicate_rows(self, seeded_warehouse):
        raw = make_orders_raw(
            [{"account_id": 1, "symbol": "AAPL", "status": "FILLED", "quantity": 10, "price": 100.0}]
        )
        trades = transform_trades(raw)
        dim_account = seeded_warehouse.execute(
            "SELECT account_key, source_id, is_current FROM dim_account"
        ).df()
        dim_instrument = seeded_warehouse.execute(
            "SELECT instrument_key, symbol FROM dim_instrument"
        ).df()
        dim_date = seeded_warehouse.execute("SELECT date_key FROM dim_date").df()

        result = validate_trades(trades, dim_account, dim_instrument, dim_date)
        first_loaded = load_fact_trades(seeded_warehouse, result.valid)
        second_loaded = load_fact_trades(seeded_warehouse, result.valid)

        assert first_loaded == 1
        assert second_loaded == 0
        count = seeded_warehouse.execute("SELECT COUNT(*) FROM fact_trades").fetchone()[0]
        assert count == 1

    def test_status_transition_updates_the_existing_row_in_place(self, seeded_warehouse):
        dim_account = seeded_warehouse.execute(
            "SELECT account_key, source_id, is_current FROM dim_account"
        ).df()
        dim_instrument = seeded_warehouse.execute(
            "SELECT instrument_key, symbol FROM dim_instrument"
        ).df()
        dim_date = seeded_warehouse.execute("SELECT date_key FROM dim_date").df()

        raw_new = make_orders_raw(
            [{"account_id": 1, "symbol": "AAPL", "status": "NEW", "executed_price": None,
              "quantity": 10, "price": 100.0}]
        )
        raw_new["id"] = "00000000-0000-0000-0000-000000000042"
        trades_new = transform_trades(raw_new)
        result_new = validate_trades(trades_new, dim_account, dim_instrument, dim_date)
        load_fact_trades(seeded_warehouse, result_new.valid)

        key_before = seeded_warehouse.execute(
            "SELECT trade_key FROM fact_trades WHERE source_order_id = ?",
            ["00000000-0000-0000-0000-000000000042"],
        ).fetchone()[0]

        raw_filled = make_orders_raw(
            [{"account_id": 1, "symbol": "AAPL", "status": "FILLED", "executed_price": 101.5,
              "quantity": 10, "price": 100.0}]
        )
        raw_filled["id"] = "00000000-0000-0000-0000-000000000042"
        trades_filled = transform_trades(raw_filled)
        result_filled = validate_trades(trades_filled, dim_account, dim_instrument, dim_date)
        load_fact_trades(seeded_warehouse, result_filled.valid)

        row = seeded_warehouse.execute(
            "SELECT trade_key, status, executed_price, trade_value FROM fact_trades "
            "WHERE source_order_id = ?",
            ["00000000-0000-0000-0000-000000000042"],
        ).fetchone()

        assert row[0] == key_before  # same surrogate key, updated in place
        assert row[1] == "FILLED"
        assert float(row[2]) == 101.5
        assert float(row[3]) == 1015.0
        total_rows = seeded_warehouse.execute("SELECT COUNT(*) FROM fact_trades").fetchone()[0]
        assert total_rows == 1

    def test_quarantined_rows_are_never_loaded_into_fact_trades(self, seeded_warehouse):
        dim_account = seeded_warehouse.execute(
            "SELECT account_key, source_id, is_current FROM dim_account"
        ).df()
        dim_instrument = seeded_warehouse.execute(
            "SELECT instrument_key, symbol FROM dim_instrument"
        ).df()
        dim_date = seeded_warehouse.execute("SELECT date_key FROM dim_date").df()

        raw = make_orders_raw([{"quantity": -5}])
        trades = transform_trades(raw)
        result = validate_trades(trades, dim_account, dim_instrument, dim_date)

        load_fact_trades(seeded_warehouse, result.valid)
        count = seeded_warehouse.execute("SELECT COUNT(*) FROM fact_trades").fetchone()[0]
        assert count == 0
        assert result.quarantined_count == 1

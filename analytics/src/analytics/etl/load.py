"""Load: idempotent upserts into the DuckDB warehouse.

Load order is fixed by docs/contracts/analytics-schema.sql: dim_date, then
dim_instrument, then dim_account, then fact_trades. A fact row loaded before
its dimensions exist would reference a key that is not there yet.

Every function is safe to re-run against the same input. Re-running
yesterday's load must not double-count, per the same contract.
"""

from __future__ import annotations

from datetime import date, timedelta

import duckdb
import pandas as pd

from analytics.db.warehouse import next_surrogate_key
from analytics.timeutil import utcnow


def load_dim_date(conn: duckdb.DuckDBPyConnection, dates: pd.DataFrame) -> int:
    """Insert any calendar day not already present. dim_date never changes
    once written, so there is nothing to update on conflict.
    """
    if dates.empty:
        return 0
    conn.register("stg_dates", dates)
    before = conn.execute("SELECT COUNT(*) FROM dim_date").fetchone()[0]
    conn.execute(
        """
        INSERT INTO dim_date
        SELECT date_key, full_date, day, month, year, quarter,
               day_of_week, day_name, month_name, is_weekday
        FROM stg_dates
        ON CONFLICT (date_key) DO NOTHING
        """
    )
    conn.unregister("stg_dates")
    after = conn.execute("SELECT COUNT(*) FROM dim_date").fetchone()[0]
    return after - before


def load_dim_instrument(conn: duckdb.DuckDBPyConnection, instruments: pd.DataFrame) -> int:
    """Type 1 upsert, merged on `symbol`. New symbols get a freshly assigned
    surrogate key; existing symbols keep theirs and have every other column
    overwritten in place.
    """
    if instruments.empty:
        return 0

    existing = conn.execute("SELECT symbol, instrument_key FROM dim_instrument").df()
    existing_keys = dict(zip(existing["symbol"], existing["instrument_key"]))

    new_symbols = [s for s in instruments["symbol"] if s not in existing_keys]
    next_key = next_surrogate_key(conn, "dim_instrument", "instrument_key")
    for offset, symbol in enumerate(new_symbols):
        existing_keys[symbol] = next_key + offset

    staged = instruments.copy()
    staged["instrument_key"] = staged["symbol"].map(existing_keys)
    staged["loaded_at"] = utcnow()

    conn.register("stg_instruments", staged)
    conn.execute(
        """
        INSERT INTO dim_instrument
            (instrument_key, symbol, name, asset_class, currency, exchange, tradable, loaded_at)
        SELECT instrument_key, symbol, name, asset_class, currency, exchange, tradable, loaded_at
        FROM stg_instruments
        ON CONFLICT (symbol) DO UPDATE SET
            name = excluded.name,
            asset_class = excluded.asset_class,
            currency = excluded.currency,
            exchange = excluded.exchange,
            tradable = excluded.tradable,
            loaded_at = excluded.loaded_at
        """
    )
    conn.unregister("stg_instruments")
    return len(new_symbols)


def load_dim_account(
    conn: duckdb.DuckDBPyConnection, accounts: pd.DataFrame, effective_date: date
) -> tuple[int, int]:
    """Type 2 upsert, merged on `account_id`.

    Returns `(new_accounts, new_versions)`. An account seen for the first
    time gets one current row. An account whose `holder_name` or `status`
    changed gets its current row closed (`end_date` set, `is_current` set to
    false) and a new current row inserted. An account with no change is left
    untouched, which is what makes a second run over the same input a no-op.
    """
    if accounts.empty:
        return (0, 0)

    current = conn.execute(
        "SELECT account_key, account_id, holder_name, status "
        "FROM dim_account WHERE is_current"
    ).df()
    current_by_id = {row.account_id: row for row in current.itertuples()}

    next_key = next_surrogate_key(conn, "dim_account", "account_key")
    new_accounts = 0
    new_versions = 0
    day_before_effective = effective_date - timedelta(days=1)
    now = utcnow()

    conn.execute("BEGIN TRANSACTION")
    try:
        for row in accounts.itertuples():
            existing = current_by_id.get(row.account_id)

            if existing is None:
                conn.execute(
                    """
                    INSERT INTO dim_account
                        (account_key, account_id, holder_name, status, effective_date,
                         end_date, is_current, source_id, loaded_at)
                    VALUES (?, ?, ?, ?, ?, NULL, TRUE, ?, ?)
                    """,
                    [next_key, row.account_id, row.holder_name, row.status,
                     effective_date, row.source_id, now],
                )
                next_key += 1
                new_accounts += 1
                continue

            unchanged = (
                existing.holder_name == row.holder_name and existing.status == row.status
            )
            if unchanged:
                continue

            conn.execute(
                "UPDATE dim_account SET end_date = ?, is_current = FALSE "
                "WHERE account_key = ?",
                [day_before_effective, existing.account_key],
            )
            conn.execute(
                """
                INSERT INTO dim_account
                    (account_key, account_id, holder_name, status, effective_date,
                     end_date, is_current, source_id, loaded_at)
                VALUES (?, ?, ?, ?, ?, NULL, TRUE, ?, ?)
                """,
                [next_key, row.account_id, row.holder_name, row.status,
                 effective_date, row.source_id, now],
            )
            next_key += 1
            new_versions += 1
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise

    return (new_accounts, new_versions)


def load_fact_trades(conn: duckdb.DuckDBPyConnection, trades: pd.DataFrame) -> int:
    """Upsert on `source_order_id`. An order revisited by a later extract (a
    status transition from NEW to FILLED, most often) updates its existing
    row in place and keeps its original `trade_key`, rather than growing a
    second row for the same order. That is what makes re-running a window
    idempotent even though orders themselves are mutable in Postgres.
    """
    if trades.empty:
        return 0

    existing = conn.execute(
        "SELECT source_order_id, trade_key FROM fact_trades"
    ).df()
    existing_keys = dict(zip(existing["source_order_id"], existing["trade_key"]))

    new_ids = [sid for sid in trades["source_order_id"] if sid not in existing_keys]
    next_key = next_surrogate_key(conn, "fact_trades", "trade_key")
    for offset, source_order_id in enumerate(new_ids):
        existing_keys[source_order_id] = next_key + offset

    staged = trades.copy()
    staged["trade_key"] = staged["source_order_id"].map(existing_keys)
    staged["loaded_at"] = utcnow()

    conn.register("stg_trades", staged)
    conn.execute(
        """
        INSERT INTO fact_trades
            (trade_key, account_key, instrument_key, date_key, side, quantity, price,
             status, executed_price, trade_value, source_order_id, created_at, loaded_at)
        SELECT trade_key, account_key, instrument_key, date_key, side, quantity, price,
               status, executed_price, trade_value, source_order_id, created_at, loaded_at
        FROM stg_trades
        ON CONFLICT (source_order_id) DO UPDATE SET
            account_key = excluded.account_key,
            instrument_key = excluded.instrument_key,
            date_key = excluded.date_key,
            side = excluded.side,
            quantity = excluded.quantity,
            price = excluded.price,
            status = excluded.status,
            executed_price = excluded.executed_price,
            trade_value = excluded.trade_value,
            created_at = excluded.created_at,
            loaded_at = excluded.loaded_at
        """
    )
    conn.unregister("stg_trades")
    return len(new_ids)


def load_quarantine(
    conn: duckdb.DuckDBPyConnection, quarantined: pd.DataFrame, stage: str
) -> int:
    """Append rejected rows. Quarantine is append-only: it is the pipeline's
    own audit trail of what it refused to load and why.
    """
    if quarantined.empty:
        return 0

    next_id = next_surrogate_key(conn, "etl_quarantine", "quarantine_id")
    staged = quarantined.copy()
    staged.insert(0, "quarantine_id", range(next_id, next_id + len(staged)))
    staged["stage"] = stage
    staged["raw_payload"] = staged["raw_payload"].astype(str)
    staged["quarantined_at"] = utcnow()

    conn.register("stg_quarantine", staged)
    conn.execute(
        """
        INSERT INTO etl_quarantine
            (quarantine_id, source_order_id, stage, reason, raw_payload, quarantined_at)
        SELECT quarantine_id, source_order_id, stage, reason, raw_payload, quarantined_at
        FROM stg_quarantine
        """
    )
    conn.unregister("stg_quarantine")
    return len(staged)


def load_candles(conn: duckdb.DuckDBPyConnection, candles: pd.DataFrame) -> int:
    """Upsert the candle cache on `(symbol, trade_date)`."""
    if candles.empty:
        return 0

    staged = candles.copy()
    staged["fetched_at"] = utcnow()
    conn.register("stg_candles", staged)
    conn.execute(
        """
        INSERT INTO stg_market_candles
            (symbol, trade_date, open, high, low, close, volume, fetched_at)
        SELECT symbol, trade_date, open, high, low, close, volume, fetched_at
        FROM stg_candles
        ON CONFLICT (symbol, trade_date) DO UPDATE SET
            open = excluded.open,
            high = excluded.high,
            low = excluded.low,
            close = excluded.close,
            volume = excluded.volume,
            fetched_at = excluded.fetched_at
        """
    )
    conn.unregister("stg_candles")
    return len(staged)

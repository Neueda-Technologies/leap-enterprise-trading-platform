"""Orchestration for the three `etl` subcommands: run, validate, backfill.

Each function owns one connection to the warehouse and one engine onto
Postgres for the duration of the call, and closes both before returning.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta

import duckdb
import pandas as pd

from analytics.config import Settings
from analytics.db import operational, warehouse
from analytics.etl import extract, load, transform, validate, watermark
from analytics.fauxnance.client import FauxnanceClient
from analytics.seed_universe import SYMBOLS
from analytics.timeutil import utcnow

logger = logging.getLogger(__name__)

# dim_date is pre-populated ahead of any fact load, per docs/contracts/analytics-schema.sql.
# Overridable so a test does not have to materialise fifteen years of dates.
_DEFAULT_DIM_DATE_FROM = date.fromisoformat(os.environ.get("ETL_DIM_DATE_FROM", "2018-01-01"))
_DEFAULT_DIM_DATE_TO = date.fromisoformat(os.environ.get("ETL_DIM_DATE_TO", "2032-12-31"))


@dataclass
class RunSummary:
    orders_extracted: int = 0
    trades_loaded: int = 0
    trades_quarantined: int = 0
    new_instruments: int = 0
    new_accounts: int = 0
    changed_accounts: int = 0
    dates_loaded: int = 0
    candles_fetched: int = 0
    candle_anomalies: int = 0
    watermark_before: datetime | None = None
    watermark_after: datetime | None = None
    quarantine_reasons: list[str] = field(default_factory=list)


def ensure_date_dimension(
    conn: duckdb.DuckDBPyConnection,
    from_date: date = _DEFAULT_DIM_DATE_FROM,
    to_date: date = _DEFAULT_DIM_DATE_TO,
) -> int:
    dates = transform.transform_dates(from_date, to_date)
    return load.load_dim_date(conn, dates)


def _current_dim_account(conn: duckdb.DuckDBPyConnection) -> pd.DataFrame:
    return conn.execute(
        "SELECT account_key, account_id, source_id, is_current FROM dim_account"
    ).df()


def _current_dim_instrument(conn: duckdb.DuckDBPyConnection) -> pd.DataFrame:
    return conn.execute("SELECT instrument_key, symbol FROM dim_instrument").df()


def _current_dim_date(conn: duckdb.DuckDBPyConnection) -> pd.DataFrame:
    return conn.execute("SELECT date_key FROM dim_date").df()


def _load_dimensions_and_facts(
    conn: duckdb.DuckDBPyConnection,
    settings: Settings,
    accounts_raw: pd.DataFrame,
    instruments_raw: pd.DataFrame,
    orders_raw: pd.DataFrame,
    effective_date: date,
    summary: RunSummary,
) -> None:
    ensure_date_dimension(conn)
    summary.dates_loaded = conn.execute("SELECT COUNT(*) FROM dim_date").fetchone()[0]

    dim_instruments = transform.transform_instruments(instruments_raw)
    summary.new_instruments = load.load_dim_instrument(conn, dim_instruments)

    dim_accounts = transform.transform_accounts(accounts_raw, effective_date)
    summary.new_accounts, summary.changed_accounts = load.load_dim_account(
        conn, dim_accounts, effective_date
    )

    trades = transform.transform_trades(orders_raw)
    summary.orders_extracted = len(orders_raw)

    if not trades.empty and settings.fauxnance.api_key:
        symbols = sorted(set(trades["symbol"]) | set(SYMBOLS))
        client = FauxnanceClient(
            base_url=settings.fauxnance.base_url,
            api_key=settings.fauxnance.api_key,
            timeout_seconds=settings.fauxnance.timeout_seconds,
            max_retries=settings.fauxnance.max_retries,
        )
        from_date = trades["created_at"].min().date()
        to_date = trades["created_at"].max().date()
        candles = extract.extract_candles(client, symbols, from_date, to_date)
        summary.candles_fetched = load.load_candles(conn, candles)
    else:
        candles = pd.DataFrame(columns=["symbol", "trade_date"])
        if trades.empty:
            logger.info("No orders extracted, skipping the Fauxnance candle pull.")
        else:
            logger.warning("FAUXNANCE_API_KEY not set, skipping the Fauxnance candle pull.")

    result = validate.validate_trades(
        trades,
        _current_dim_account(conn),
        _current_dim_instrument(conn),
        _current_dim_date(conn),
    )
    summary.trades_loaded = load.load_fact_trades(conn, result.valid)
    summary.trades_quarantined = load.load_quarantine(conn, result.quarantined, stage="fact_trades")
    if not result.quarantined.empty:
        summary.quarantine_reasons = sorted(set(result.quarantined["reason"]))

    anomalies = validate.check_candle_reasonableness(result.valid, candles)
    summary.candle_anomalies = len(anomalies)
    if not anomalies.empty:
        logger.warning(
            "%d fill(s) landed outside the Fauxnance daily range, logged as anomalies, "
            "not quarantined.",
            len(anomalies),
        )


def run(settings: Settings) -> RunSummary:
    """`etl run`: incremental load of everything created since the watermark."""
    summary = RunSummary()
    conn = warehouse.connect(settings.warehouse.path)
    engine = operational.get_engine(settings.postgres)
    try:
        summary.watermark_before = watermark.get_watermark(conn)
        accounts_raw = extract.extract_accounts(engine)
        instruments_raw = extract.extract_instruments(engine)
        orders_raw = extract.extract_orders_since(engine, summary.watermark_before)

        _load_dimensions_and_facts(
            conn, settings, accounts_raw, instruments_raw, orders_raw, date.today(), summary
        )

        if not orders_raw.empty:
            new_watermark = pd.to_datetime(orders_raw["created_on"]).max().to_pydatetime()
            watermark.set_watermark(conn, new_watermark)
            summary.watermark_after = new_watermark
        else:
            summary.watermark_after = summary.watermark_before
    finally:
        engine.dispose()
        conn.close()
    return summary


def backfill(settings: Settings, from_date: date, to_date: date) -> RunSummary:
    """`etl backfill --from --to`: reload a specific date range, idempotently.

    Does not depend on or reset the incremental watermark used by `etl run`
    other than to advance it if this range extends past it, since a re-run
    of a backfilled window must stay idempotent whichever command re-runs it.
    """
    if from_date > to_date:
        raise ValueError(f"--from {from_date} is after --to {to_date}")

    summary = RunSummary()
    conn = warehouse.connect(settings.warehouse.path)
    engine = operational.get_engine(settings.postgres)
    try:
        summary.watermark_before = watermark.get_watermark(conn)
        accounts_raw = extract.extract_accounts(engine)
        instruments_raw = extract.extract_instruments(engine)
        orders_raw = extract.extract_orders_range(engine, from_date, to_date)

        _load_dimensions_and_facts(
            conn, settings, accounts_raw, instruments_raw, orders_raw, date.today(), summary
        )

        if not orders_raw.empty:
            batch_max = pd.to_datetime(orders_raw["created_on"]).max().to_pydatetime()
            if summary.watermark_before is None or batch_max > summary.watermark_before:
                watermark.set_watermark(conn, batch_max)
                summary.watermark_after = batch_max
            else:
                summary.watermark_after = summary.watermark_before
        else:
            summary.watermark_after = summary.watermark_before
    finally:
        engine.dispose()
        conn.close()
    return summary


def validate_warehouse(settings: Settings, reconcile_days: int = 7) -> dict:
    """`etl validate`: post-load checks against the warehouse as it stands,
    plus a reconciliation against Postgres for the last `reconcile_days`.

    Does not extract or load anything. Safe to run at any time, including
    against a warehouse with no Postgres connectivity, in which case the
    reconciliation section is skipped and reported as such.
    """
    conn = warehouse.connect(settings.warehouse.path)
    try:
        fact_trades = conn.execute("SELECT * FROM fact_trades").df()
        report = {
            "row_counts": {
                "fact_trades": conn.execute("SELECT COUNT(*) FROM fact_trades").fetchone()[0],
                "dim_account": conn.execute("SELECT COUNT(*) FROM dim_account").fetchone()[0],
                "dim_instrument": conn.execute("SELECT COUNT(*) FROM dim_instrument").fetchone()[0],
                "dim_date": conn.execute("SELECT COUNT(*) FROM dim_date").fetchone()[0],
                "etl_quarantine": conn.execute("SELECT COUNT(*) FROM etl_quarantine").fetchone()[0],
            },
            "nulls": validate.row_count_and_null_report(
                fact_trades,
                ["account_key", "instrument_key", "date_key", "trade_value", "source_order_id"],
            )["nulls"],
            "orphan_fact_rows": _count_orphans(conn),
            "duplicate_current_accounts": _count_duplicate_current_accounts(conn),
            "reconciliation": None,
        }

        since = utcnow() - timedelta(days=reconcile_days)
        try:
            engine = operational.get_engine(settings.postgres)
            with engine.connect() as pg:
                from sqlalchemy import text

                pg_count = pg.execute(
                    text("SELECT COUNT(*) FROM orders WHERE created_on >= :since"),
                    {"since": since},
                ).scalar_one()
            engine.dispose()
            wh_count = conn.execute(
                "SELECT COUNT(*) FROM fact_trades WHERE created_at >= ?", [since]
            ).fetchone()[0]
            report["reconciliation"] = {
                "window_days": reconcile_days,
                "postgres_orders": pg_count,
                "warehouse_fact_trades": wh_count,
                "matches": pg_count == wh_count,
            }
        except Exception as exc:  # noqa: BLE001 - reported, not raised
            report["reconciliation"] = {"skipped": True, "reason": str(exc)}

        return report
    finally:
        conn.close()


def _count_orphans(conn: duckdb.DuckDBPyConnection) -> dict:
    return {
        "missing_account": conn.execute(
            "SELECT COUNT(*) FROM fact_trades f "
            "LEFT JOIN dim_account a ON a.account_key = f.account_key "
            "WHERE a.account_key IS NULL"
        ).fetchone()[0],
        "missing_instrument": conn.execute(
            "SELECT COUNT(*) FROM fact_trades f "
            "LEFT JOIN dim_instrument i ON i.instrument_key = f.instrument_key "
            "WHERE i.instrument_key IS NULL"
        ).fetchone()[0],
        "missing_date": conn.execute(
            "SELECT COUNT(*) FROM fact_trades f "
            "LEFT JOIN dim_date d ON d.date_key = f.date_key "
            "WHERE d.date_key IS NULL"
        ).fetchone()[0],
    }


def _count_duplicate_current_accounts(conn: duckdb.DuckDBPyConnection) -> int:
    row = conn.execute(
        """
        SELECT COUNT(*) FROM (
            SELECT account_id FROM dim_account
            WHERE is_current
            GROUP BY account_id
            HAVING COUNT(*) > 1
        )
        """
    ).fetchone()
    return row[0]

"""Extract: read from the operational database and from Fauxnance.

Every function here only reads. The accounts, instruments and orders queries
run against the `analytics_reader` role (docs/contracts/database-schema.sql).
Nothing in this module writes to Postgres or calls Fauxnance with a mutating
verb, because Fauxnance has none.
"""

from __future__ import annotations

import logging
from datetime import date, datetime

import pandas as pd
from sqlalchemy import Engine, text

from analytics.fauxnance.client import Candle, FauxnanceClient

logger = logging.getLogger(__name__)


def extract_accounts(engine: Engine) -> pd.DataFrame:
    """Every account, current state only. accounts is not versioned in Postgres;
    the versioning happens on load, into dim_account.
    """
    query = text(
        "SELECT id AS source_id, account_id, holder_name, status "
        "FROM accounts ORDER BY id"
    )
    with engine.connect() as conn:
        return pd.read_sql(query, conn)


def extract_instruments(engine: Engine) -> pd.DataFrame:
    query = text(
        "SELECT symbol, name, asset_class, currency, tradable "
        "FROM instruments ORDER BY symbol"
    )
    with engine.connect() as conn:
        return pd.read_sql(query, conn)


def extract_orders_since(engine: Engine, since: datetime | None) -> pd.DataFrame:
    """Orders created since the watermark. `since` is exclusive: an order
    already loaded at exactly that timestamp is not re-extracted.

    Reads only terminal-looking columns plus the operational primary key.
    `orders` is append-mostly (rows update in place from NEW to a terminal
    status), so a row already loaded can come back with new values, and the
    load step upserts on `source_order_id` rather than assuming a first
    write is the only write.
    """
    query = text(
        "SELECT id, account_id, symbol, side, quantity, price, status, "
        "executed_price, executed_on, reject_reason, created_on "
        "FROM orders WHERE (:since IS NULL OR created_on > :since) "
        "ORDER BY created_on"
    )
    with engine.connect() as conn:
        return pd.read_sql(query, conn, params={"since": since})


def extract_orders_range(engine: Engine, from_date: date, to_date: date) -> pd.DataFrame:
    """Orders created within `[from_date, to_date]`, inclusive. Used by `etl backfill`."""
    query = text(
        "SELECT id, account_id, symbol, side, quantity, price, status, "
        "executed_price, executed_on, reject_reason, created_on "
        "FROM orders "
        "WHERE created_on >= :from_date AND created_on < :to_date_exclusive "
        "ORDER BY created_on"
    )
    with engine.connect() as conn:
        return pd.read_sql(
            query,
            conn,
            params={
                "from_date": datetime.combine(from_date, datetime.min.time()),
                # to_date is inclusive at the day level, so the upper bound
                # used in the query is the day after it, exclusive.
                "to_date_exclusive": datetime.combine(
                    date.fromordinal(to_date.toordinal() + 1), datetime.min.time()
                ),
            },
        )


def extract_candles(
    client: FauxnanceClient, symbols: list[str], from_date: date, to_date: date
) -> pd.DataFrame:
    """Pull EOD candles for each symbol over the range, one Fauxnance call per
    symbol. A symbol that fails after retries is logged and skipped rather
    than failing the whole extract: candles only feed a soft reasonableness
    check, not the fact load itself, so one bad symbol should not block the
    batch that funds and positions actually depend on.
    """
    rows: list[Candle] = []
    for symbol in symbols:
        try:
            rows.extend(client.get_candles(symbol, from_date, to_date))
        except Exception:
            logger.exception("Failed to fetch Fauxnance candles for %s, skipping", symbol)

    if not rows:
        return pd.DataFrame(
            columns=["symbol", "trade_date", "open", "high", "low", "close", "volume"]
        )

    return pd.DataFrame(
        {
            "symbol": [c.symbol for c in rows],
            "trade_date": [c.trade_date for c in rows],
            "open": [c.open for c in rows],
            "high": [c.high for c in rows],
            "low": [c.low for c in rows],
            "close": [c.close for c in rows],
            "volume": [c.volume for c in rows],
        }
    )

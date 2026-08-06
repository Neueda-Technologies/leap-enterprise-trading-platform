"""Transform: reshape extracted rows into the star schema.

Every function here is pure: a DataFrame in, a DataFrame out, no database
connection and no HTTP call. That is what makes this module the one pytest
exercises directly, with no faked infrastructure required.
"""

from __future__ import annotations

from datetime import date, timedelta

import pandas as pd

VALID_SIDES = frozenset({"BUY", "SELL"})
VALID_STATUSES = frozenset({"NEW", "FILLED", "REJECTED", "CANCELLED"})

_DAY_NAMES = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
]
_MONTH_NAMES = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
]


def derive_exchange(symbol: str) -> str:
    """Map a Fauxnance symbol to a venue, per the scheme documented on
    `instruments.symbol` in docs/contracts/database-schema.sql and repeated
    on `dim_instrument.exchange` in docs/contracts/analytics-schema.sql.
    """
    if symbol.startswith("FX:"):
        return "FX"
    if symbol.startswith("X:"):
        return "CRYPTO"
    if symbol.endswith(".NS"):
        return "NSE"
    if symbol.endswith(".BO"):
        return "BSE"
    return "US"


def transform_instruments(raw: pd.DataFrame) -> pd.DataFrame:
    """dim_instrument candidate rows. Type 1: the caller overwrites in place,
    there is no history to preserve here.
    """
    if raw.empty:
        return pd.DataFrame(
            columns=["symbol", "name", "asset_class", "currency", "exchange", "tradable"]
        )

    out = raw.copy()
    out["exchange"] = out["symbol"].map(derive_exchange)
    return out[["symbol", "name", "asset_class", "currency", "exchange", "tradable"]]


def transform_accounts(raw: pd.DataFrame, effective_date: date) -> pd.DataFrame:
    """dim_account candidate rows for `effective_date`. Type 2: the caller
    decides, per account, whether this candidate is a new version by
    comparing it against the current row already in the warehouse.
    """
    if raw.empty:
        return pd.DataFrame(
            columns=["source_id", "account_id", "holder_name", "status", "effective_date"]
        )

    out = raw[["source_id", "account_id", "holder_name", "status"]].copy()
    out["effective_date"] = effective_date
    return out


def transform_dates(from_date: date, to_date: date) -> pd.DataFrame:
    """One row per calendar day in `[from_date, to_date]`, inclusive."""
    if from_date > to_date:
        raise ValueError(f"from_date {from_date} is after to_date {to_date}")

    days = (to_date - from_date).days + 1
    dates = [from_date + timedelta(days=i) for i in range(days)]

    return pd.DataFrame(
        {
            "date_key": [_date_key(d) for d in dates],
            "full_date": dates,
            "day": [d.day for d in dates],
            "month": [d.month for d in dates],
            "year": [d.year for d in dates],
            "quarter": [(d.month - 1) // 3 + 1 for d in dates],
            "day_of_week": [d.isoweekday() for d in dates],
            "day_name": [_DAY_NAMES[d.weekday()] for d in dates],
            "month_name": [_MONTH_NAMES[d.month - 1] for d in dates],
            "is_weekday": [d.isoweekday() <= 5 for d in dates],
        }
    )


def _date_key(d: date) -> int:
    return d.year * 10_000 + d.month * 100 + d.day


def compute_trade_value(quantity: float, price: float, executed_price, status: str) -> float:
    """quantity multiplied by executed_price where the order filled,
    otherwise quantity multiplied by price. Documented on `fact_trades.trade_value`
    in docs/contracts/analytics-schema.sql. Never sum or average `price` itself.
    """
    unit_price = executed_price if (status == "FILLED" and pd.notna(executed_price)) else price
    return round(float(quantity) * float(unit_price), 2)


def transform_trades(raw: pd.DataFrame) -> pd.DataFrame:
    """fact_trades candidate rows, still keyed by natural keys (the Postgres
    `account_id` surrogate and the instrument `symbol`), not yet resolved to
    dim_account.account_key or dim_instrument.instrument_key. Key resolution
    happens in `analytics.etl.load`, against whatever is current in the
    warehouse at load time.
    """
    if raw.empty:
        return pd.DataFrame(
            columns=[
                "source_order_id",
                "source_account_id",
                "symbol",
                "side",
                "quantity",
                "price",
                "status",
                "executed_price",
                "trade_value",
                "created_at",
                "date_key",
            ]
        )

    out = pd.DataFrame(
        {
            "source_order_id": raw["id"].astype(str),
            "source_account_id": raw["account_id"],
            "symbol": raw["symbol"],
            "side": raw["side"],
            "quantity": raw["quantity"],
            "price": raw["price"].astype(float),
            "status": raw["status"],
            "executed_price": raw["executed_price"],
            "created_at": pd.to_datetime(raw["created_on"]),
        }
    )
    out["trade_value"] = [
        compute_trade_value(q, p, ep, s)
        for q, p, ep, s in zip(
            out["quantity"], out["price"], out["executed_price"], out["status"]
        )
    ]
    out["date_key"] = out["created_at"].dt.strftime("%Y%m%d").astype(int)
    return out

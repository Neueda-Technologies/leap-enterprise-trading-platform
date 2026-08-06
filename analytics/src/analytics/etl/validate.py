"""Validate: the checks that run before load, per the "LOAD ORDER AND DATA
QUALITY" section of docs/contracts/analytics-schema.sql.

Every check here either passes a row through unchanged or quarantines it
with a reason. Nothing here raises for a single bad row: the batch keeps
going and the bad row is reported, which is the whole point of a quarantine
table instead of a bare `try` block around the load.
"""

from __future__ import annotations

from dataclasses import dataclass

import pandas as pd

from analytics.etl.transform import VALID_SIDES, VALID_STATUSES, compute_trade_value
from analytics.timeutil import utcnow

_TRADE_VALUE_TOLERANCE = 0.01


@dataclass(frozen=True)
class ValidationResult:
    valid: pd.DataFrame
    quarantined: pd.DataFrame

    @property
    def valid_count(self) -> int:
        return len(self.valid)

    @property
    def quarantined_count(self) -> int:
        return len(self.quarantined)


def _empty_quarantine() -> pd.DataFrame:
    return pd.DataFrame(columns=["source_order_id", "reason", "raw_payload"])


def validate_trades(
    trades: pd.DataFrame,
    dim_account: pd.DataFrame,
    dim_instrument: pd.DataFrame,
    dim_date: pd.DataFrame,
) -> ValidationResult:
    """Resolve dimension keys and apply every pre-load check.

    `dim_account` and `dim_instrument` are the current warehouse contents,
    loaded before facts per the mandated load order. A row that cannot
    resolve a key is quarantined rather than loaded with a placeholder,
    because a placeholder key hides the real fault (docs/contracts/analytics-schema.sql).
    """
    if trades.empty:
        return ValidationResult(valid=trades.copy(), quarantined=_empty_quarantine())

    working = trades.copy()
    working["_reasons"] = [[] for _ in range(len(working))]

    def flag(mask: pd.Series, reason: str) -> None:
        for idx in working.index[mask]:
            working.at[idx, "_reasons"].append(reason)

    flag(working["quantity"] <= 0, "quantity must be greater than zero")
    flag(working["price"] <= 0, "price must be greater than zero")
    flag(~working["side"].isin(VALID_SIDES), "side is not BUY or SELL")
    flag(~working["status"].isin(VALID_STATUSES), "status is not a recognised order status")

    recomputed = [
        compute_trade_value(q, p, ep, s)
        for q, p, ep, s in zip(
            working["quantity"], working["price"], working["executed_price"], working["status"]
        )
    ]
    mismatch = (pd.Series(recomputed, index=working.index) - working["trade_value"]).abs() \
        > _TRADE_VALUE_TOLERANCE
    flag(mismatch, "trade_value does not match quantity * price recomputed")

    # Within-batch duplicates: keep the most recently created row, quarantine
    # the rest. A genuine duplicate should not happen given the Postgres
    # primary key on orders.id, but a batch spanning a watermark overlap can
    # otherwise double-submit the same order to the load step.
    is_dupe = working.duplicated(subset="source_order_id", keep="last")
    flag(is_dupe, "duplicate source_order_id within this batch")

    # Referential integrity into the dimensions, resolved here so a row that
    # cannot resolve is quarantined instead of silently dropped by an inner
    # join later.
    current_accounts = dim_account.loc[dim_account["is_current"]]
    working = working.merge(
        current_accounts[["source_id", "account_key"]],
        how="left",
        left_on="source_account_id",
        right_on="source_id",
        suffixes=("", "_acct"),
    )
    flag(working["account_key"].isna(), "no current dim_account row for this account")

    working = working.merge(
        dim_instrument[["symbol", "instrument_key"]], how="left", on="symbol"
    )
    flag(working["instrument_key"].isna(), "no dim_instrument row for this symbol")

    known_date_keys = set(dim_date["date_key"])
    flag(~working["date_key"].isin(known_date_keys), "date_key not present in dim_date")

    has_reason = working["_reasons"].map(bool)
    quarantined_rows = working.loc[has_reason].copy()
    valid_rows = working.loc[~has_reason].copy()

    quarantined = pd.DataFrame(
        {
            "source_order_id": quarantined_rows["source_order_id"],
            "reason": quarantined_rows["_reasons"].map("; ".join),
            "raw_payload": quarantined_rows.drop(columns=["_reasons"]).astype(str).to_dict(
                orient="records"
            ),
        }
    ) if not quarantined_rows.empty else _empty_quarantine()

    valid_rows = valid_rows.drop(
        columns=["_reasons", "source_id"], errors="ignore"
    ).astype({"account_key": "int64", "instrument_key": "int64"})

    return ValidationResult(valid=valid_rows, quarantined=quarantined)


def check_candle_reasonableness(
    trades: pd.DataFrame, candles: pd.DataFrame
) -> pd.DataFrame:
    """Soft check, not a rejection: for FILLED orders, does the executed price
    fall inside that day's traded range from Fauxnance?

    Returns the subset of rows that fail the check, for logging. Fauxnance
    candles are end-of-day and delayed (docs/DECISIONS.md, decision 2), and a
    real fill can legitimately sit outside a same-day OHLC range around the
    open or close, so this is an anomaly worth a warning, not grounds to
    quarantine a trade that otherwise passed every hard check.
    """
    if trades.empty or candles.empty:
        return trades.iloc[0:0]

    filled = trades.loc[trades["status"] == "FILLED"].copy()
    if filled.empty:
        return filled

    filled["trade_date"] = pd.to_datetime(filled["created_at"]).dt.date
    merged = filled.merge(candles, how="inner", on=["symbol", "trade_date"])
    if merged.empty:
        return merged

    out_of_range = (merged["executed_price"] < merged["low"]) | (
        merged["executed_price"] > merged["high"]
    )
    return merged.loc[out_of_range]


def row_count_and_null_report(df: pd.DataFrame, required_columns: list[str]) -> dict:
    """Row counts and null counts on the columns that must never be null.
    Used by `etl validate` for a quick post-load sanity report.
    """
    return {
        "row_count": len(df),
        "nulls": {col: int(df[col].isna().sum()) for col in required_columns if col in df},
        "checked_at": utcnow().isoformat(),
    }

"""Plain data builders shared across test modules. Not a conftest, so it can
be imported directly (`from factories import make_orders_raw`) without
relying on pytest's fixture-discovery machinery.
"""

from __future__ import annotations

from datetime import datetime

import pandas as pd


def make_orders_raw(rows: list[dict]) -> pd.DataFrame:
    """Build a DataFrame shaped like `analytics.etl.extract.extract_orders_since`
    returns, from a list of partial row dicts. Fills in defaults for any
    column not given.
    """
    defaults = {
        "id": "00000000-0000-0000-0000-000000000000",
        "account_id": 1,
        "symbol": "AAPL",
        "side": "BUY",
        "quantity": 10,
        "price": 100.00,
        "status": "FILLED",
        "executed_price": 100.00,
        "executed_on": datetime(2026, 1, 15, 9, 30),
        "reject_reason": None,
        "created_on": datetime(2026, 1, 15, 9, 29),
    }
    full_rows = []
    for i, row in enumerate(rows):
        merged = {**defaults, **row}
        if merged["id"] == defaults["id"]:
            merged["id"] = f"00000000-0000-0000-0000-{i:012d}"
        full_rows.append(merged)
    return pd.DataFrame(full_rows)

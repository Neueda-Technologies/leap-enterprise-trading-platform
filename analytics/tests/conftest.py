from __future__ import annotations

import sys
from datetime import date
from pathlib import Path

import pandas as pd
import pytest

from analytics.db.warehouse import connect
from analytics.etl.load import load_dim_account, load_dim_date, load_dim_instrument
from analytics.etl.transform import transform_accounts, transform_dates, transform_instruments
from analytics.seed_universe import ACCOUNT_IDS, SYMBOLS

sys.path.insert(0, str(Path(__file__).parent))

TEST_EFFECTIVE_DATE = date(2026, 1, 1)


@pytest.fixture()
def warehouse_conn(tmp_path):
    conn = connect(str(tmp_path / "test.duckdb"))
    yield conn
    conn.close()


@pytest.fixture()
def seed_accounts_raw() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "source_id": list(ACCOUNT_IDS),
            "account_id": [f"ACC-{i:06d}" for i in ACCOUNT_IDS],
            "holder_name": [f"Holder {i}" for i in ACCOUNT_IDS],
            "status": ["ACTIVE"] * len(ACCOUNT_IDS),
        }
    )


@pytest.fixture()
def seed_instruments_raw() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "symbol": list(SYMBOLS),
            "name": [f"{s} Inc." for s in SYMBOLS],
            "asset_class": ["ETF" if s == "SPY" else "EQUITY" for s in SYMBOLS],
            "currency": ["USD"] * len(SYMBOLS),
            "tradable": [True] * len(SYMBOLS),
        }
    )


@pytest.fixture()
def seeded_warehouse(warehouse_conn, seed_accounts_raw, seed_instruments_raw):
    """A warehouse with dim_date, dim_instrument and dim_account already
    loaded from the canonical seed universe, ready for fact_trades tests.
    """
    dates = transform_dates(date(2026, 1, 1), date(2026, 12, 31))
    load_dim_date(warehouse_conn, dates)

    instruments = transform_instruments(seed_instruments_raw)
    load_dim_instrument(warehouse_conn, instruments)

    accounts = transform_accounts(seed_accounts_raw, TEST_EFFECTIVE_DATE)
    load_dim_account(warehouse_conn, accounts, TEST_EFFECTIVE_DATE)

    return warehouse_conn

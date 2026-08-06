"""The canonical seed universe used across the training material.

Kept in one place so the ETL's Fauxnance fallback, the pytest fixtures and
the dashboard's demo data all agree on the same instruments and accounts.
"""

from __future__ import annotations

SYMBOLS: tuple[str, ...] = (
    "AAPL",
    "MSFT",
    "GOOGL",
    "AMZN",
    "TSLA",
    "NVDA",
    "JPM",
    "SPY",
)

ACCOUNT_IDS: tuple[int, ...] = (1, 2, 3, 4, 5)

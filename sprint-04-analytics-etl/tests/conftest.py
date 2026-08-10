"""Shared pytest fixtures.

These load the canned responses in `fixtures/`. Nothing in the test suite is
allowed to open a socket or read a key: a suite that needs the Fauxnance API
to be up is a suite that fails on the train and gets skipped by the third
person who sees it fail.

Keep these fixtures. Add your own alongside them.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

FIXTURES_DIR = Path(__file__).resolve().parent.parent / "fixtures"


@pytest.fixture(scope="session")
def fixtures_dir() -> Path:
    """The directory holding the canned Fauxnance responses."""
    return FIXTURES_DIR


@pytest.fixture(scope="session")
def load_fixture():
    """Return a loader: `load_fixture("candles-aapl-2026-07.json")`.

    Returns the parsed JSON envelope exactly as the API would have returned
    it, so a test can hand it straight to a function that expects a response
    body.
    """

    def _load(name: str) -> dict:
        path = FIXTURES_DIR / name
        if not path.is_file():
            raise FileNotFoundError(f"No fixture named {name} in {FIXTURES_DIR}")
        return json.loads(path.read_text(encoding="utf-8"))

    return _load


@pytest.fixture()
def aapl_response(load_fixture) -> dict:
    """A well-formed candle response: nine US trading days, one calendar gap."""
    return load_fixture("candles-aapl-2026-07.json")


@pytest.fixture()
def infy_response(load_fixture) -> dict:
    """A well-formed candle response in a second currency, with a null volume."""
    return load_fixture("candles-infy-ns-2026-07.json")


@pytest.fixture()
def malformed_response(load_fixture) -> dict:
    """The deliberately corrupted response. See fixtures/README.md for the defects."""
    return load_fixture("candles-malformed.json")

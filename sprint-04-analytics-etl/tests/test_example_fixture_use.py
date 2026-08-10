"""EXAMPLE. Delete this file once your own tests use the fixtures.

It exists to show the mechanics: a fixture from `conftest.py` arrives as an
argument, the parsed envelope is an ordinary dictionary, and no network is
involved. It asserts things about the canned data rather than about your code,
which is why it passes on an empty scaffold and why it is worth nothing as
evidence.

Your real tests go in files named for what they cover, `test_transform.py` for
the transform. At least one of them must feed the malformed fixture through
your transform and assert what happens to each bad row. Declare that test in
`manifest.env` so the check harness can run it.
"""

from __future__ import annotations


def test_example_the_canned_response_carries_candles(aapl_response):
    """EXAMPLE: replace with a test of your own code."""
    candles = aapl_response["data"]["candles"]

    assert aapl_response["data"]["symbol"] == "AAPL"
    assert len(candles) == 9
    assert candles[0]["date"] == "2026-07-01"
    assert set(candles[0]) >= {"date", "open", "high", "low", "close", "volume"}

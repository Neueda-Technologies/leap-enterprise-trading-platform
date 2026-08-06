from __future__ import annotations

from datetime import date

import pytest

from analytics.fauxnance.client import Candle, FauxnanceClient, FauxnanceError


class FakeResponse:
    def __init__(self, status_code: int, json_body: dict | None = None, headers: dict | None = None):
        self.status_code = status_code
        self._json_body = json_body or {}
        self.headers = headers or {}
        self.text = str(json_body)

    def json(self):
        return self._json_body


class FakeSession:
    """A faked HTTP layer. Queue up responses (or exceptions) and this
    session hands them out in order, recording every call it was made with.
    No socket is ever opened, per the "no network in tests" rule.
    """

    def __init__(self, responses: list):
        self._responses = list(responses)
        self.calls: list[dict] = []

    def get(self, url, params=None, headers=None, timeout=None):
        self.calls.append({"url": url, "params": params, "headers": headers, "timeout": timeout})
        item = self._responses.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


def _candle_envelope(rows: list[dict]) -> dict:
    return {"data": {"candles": rows}}


def make_client(session: FakeSession, max_retries: int = 4, api_key: str | None = "test-key") -> FauxnanceClient:
    return FauxnanceClient(
        base_url="https://y4t9nq2bqf.execute-api.eu-west-2.amazonaws.com/v1",
        api_key=api_key,
        max_retries=max_retries,
        session=session,
        sleep=lambda seconds: None,  # no real waiting in tests
    )


class TestGetCandlesHappyPath:
    def test_parses_the_envelope_into_candles(self):
        session = FakeSession(
            [
                FakeResponse(
                    200,
                    _candle_envelope(
                        [
                            {
                                "date": "2026-01-15",
                                "open": 100.0,
                                "high": 105.0,
                                "low": 99.0,
                                "close": 103.0,
                                "volume": 1_000_000,
                            }
                        ]
                    ),
                )
            ]
        )
        client = make_client(session)
        candles = client.get_candles("AAPL", date(2026, 1, 15), date(2026, 1, 15))
        assert candles == [Candle("AAPL", date(2026, 1, 15), 100.0, 105.0, 99.0, 103.0, 1_000_000)]

    def test_sends_the_api_key_header_and_date_range_params(self):
        session = FakeSession([FakeResponse(200, _candle_envelope([]))])
        client = make_client(session, api_key="secret-123")
        client.get_candles("AAPL", date(2026, 1, 1), date(2026, 1, 31))
        call = session.calls[0]
        assert call["headers"]["X-Api-Key"] == "secret-123"
        assert call["params"] == {"from": "2026-01-01", "to": "2026-01-31"}
        assert call["url"].endswith("/candles/AAPL")

    def test_empty_candle_list_is_not_an_error(self):
        session = FakeSession([FakeResponse(200, _candle_envelope([]))])
        client = make_client(session)
        candles = client.get_candles("SPY", date(2026, 1, 1), date(2026, 1, 2))
        assert candles == []


class TestRetryWithBackoff:
    def test_retries_on_500_then_succeeds(self):
        session = FakeSession(
            [
                FakeResponse(500),
                FakeResponse(500),
                FakeResponse(200, _candle_envelope([])),
            ]
        )
        client = make_client(session, max_retries=4)
        candles = client.get_candles("AAPL", date(2026, 1, 1), date(2026, 1, 1))
        assert candles == []
        assert len(session.calls) == 3

    def test_retries_on_429_quota_response(self):
        session = FakeSession([FakeResponse(429), FakeResponse(200, _candle_envelope([]))])
        client = make_client(session, max_retries=4)
        client.get_candles("AAPL", date(2026, 1, 1), date(2026, 1, 1))
        assert len(session.calls) == 2

    def test_gives_up_after_max_retries_and_raises_fauxnance_error(self):
        session = FakeSession([FakeResponse(503)] * 5)
        client = make_client(session, max_retries=4)
        with pytest.raises(FauxnanceError):
            client.get_candles("AAPL", date(2026, 1, 1), date(2026, 1, 1))
        assert len(session.calls) == 5  # the original attempt plus 4 retries

    def test_non_retryable_4xx_fails_immediately_without_retrying(self):
        session = FakeSession([FakeResponse(404)])
        client = make_client(session, max_retries=4)
        with pytest.raises(FauxnanceError):
            client.get_candles("NOTASYMBOL", date(2026, 1, 1), date(2026, 1, 1))
        assert len(session.calls) == 1

    def test_network_exception_is_retried(self):
        import requests

        session = FakeSession(
            [requests.ConnectionError("boom"), FakeResponse(200, _candle_envelope([]))]
        )
        client = make_client(session, max_retries=4)
        candles = client.get_candles("AAPL", date(2026, 1, 1), date(2026, 1, 1))
        assert candles == []
        assert len(session.calls) == 2

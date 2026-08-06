from __future__ import annotations

import pytest
from conftest import FakeResponse, FakeSession

from market_data_poller.fauxnance import (
    FauxnanceClient,
    FauxnanceError,
    QuotaExhaustedError,
)


def quote_entry(symbol: str, price: float = 232.71, stale: bool = False) -> dict:
    return {
        "symbol": symbol,
        "source": "cache",
        "stale": stale,
        "quote": {
            "symbol": symbol,
            "price": price,
            "currency": "USD",
            "change": 0.21,
            "changePercent": 0.09,
            "previousClose": 232.50,
            "asOf": "2026-09-28T09:14:58Z",
            "marketState": "open",
        },
    }


def body(*entries: dict) -> dict:
    return {"data": {"quotes": list(entries)}, "meta": {"asOf": "2026-09-28T09:15:00Z"}}


def client(*responses) -> tuple[FauxnanceClient, FakeSession]:
    session = FakeSession(responses)
    return (
        FauxnanceClient("https://fauxnance.test/v1", "test-key", 5.0, session=session),
        session,
    )


def test_a_batch_is_one_request_with_a_comma_separated_symbol_list():
    api, session = client(FakeResponse(200, body(quote_entry("AAPL"), quote_entry("MSFT"))))

    result = api.batch_quotes(["AAPL", "MSFT"])

    assert len(session.calls) == 1
    assert session.calls[0]["params"] == {"symbols": "AAPL,MSFT"}
    assert [q.symbol for q in result.quotes] == ["AAPL", "MSFT"]


def test_the_api_key_travels_in_the_header_not_the_query_string():
    api, session = client(FakeResponse(200, body(quote_entry("AAPL"))))

    api.batch_quotes(["AAPL"])

    assert session.headers["X-Api-Key"] == "test-key"
    assert "apiKey" not in session.calls[0]["params"]


def test_quote_fields_are_mapped_onto_the_payload_shape():
    api, _ = client(FakeResponse(200, body(quote_entry("AAPL", price=232.71, stale=True))))

    quote = api.batch_quotes(["AAPL"]).quotes[0]

    assert quote.price == 232.71
    assert quote.currency == "USD"
    assert quote.change_percent == 0.09
    assert quote.previous_close == 232.50
    assert quote.market_state == "open"
    assert quote.as_of == "2026-09-28T09:14:58Z"
    # Staleness sits on the batch entry, beside the quote rather than inside it.
    assert quote.stale is True


def test_one_bad_symbol_does_not_cost_the_others():
    api, _ = client(
        FakeResponse(
            200,
            body(
                quote_entry("AAPL"),
                {"symbol": "NOPE", "error": {"code": "SYMBOL_NOT_FOUND", "message": "no"}},
                quote_entry("MSFT"),
            ),
        )
    )

    result = api.batch_quotes(["AAPL", "NOPE", "MSFT"])

    assert [q.symbol for q in result.quotes] == ["AAPL", "MSFT"]
    assert result.failed_symbols == ("NOPE",)


def test_a_quote_with_no_price_is_dropped_rather_than_published():
    entry = quote_entry("AAPL")
    entry["quote"].pop("price")
    api, _ = client(FakeResponse(200, body(entry, quote_entry("MSFT"))))

    result = api.batch_quotes(["AAPL", "MSFT"])

    assert [q.symbol for q in result.quotes] == ["MSFT"]
    assert result.failed_symbols == ("AAPL",)


def test_a_symbol_missing_from_the_response_is_reported_as_failed():
    api, _ = client(FakeResponse(200, body(quote_entry("AAPL"))))

    result = api.batch_quotes(["AAPL", "MSFT"])

    assert result.failed_symbols == ("MSFT",)


def test_an_unrecognised_body_yields_no_quotes_rather_than_an_exception():
    api, _ = client(FakeResponse(200, {"unexpected": True}))

    result = api.batch_quotes(["AAPL"])

    assert result.quotes == ()
    assert result.failed_symbols == ("AAPL",)


def test_a_quota_rejection_is_its_own_error_because_retrying_it_is_pointless():
    api, _ = client(FakeResponse(429, {"error": {"code": "RATE_LIMITED"}}))

    with pytest.raises(QuotaExhaustedError):
        api.batch_quotes(["AAPL"])


def test_a_server_error_is_retryable():
    api, _ = client(FakeResponse(503, {"error": {"code": "UPSTREAM_UNAVAILABLE"}}))

    with pytest.raises(FauxnanceError):
        api.batch_quotes(["AAPL"])


def test_a_transport_failure_is_wrapped():
    api, _ = client(OSError("connection reset"))

    with pytest.raises(FauxnanceError):
        api.batch_quotes(["AAPL"])


def test_a_body_that_is_not_json_is_wrapped():
    api, _ = client(FakeResponse(200, malformed=True))

    with pytest.raises(FauxnanceError):
        api.batch_quotes(["AAPL"])


def test_an_empty_symbol_list_costs_no_request():
    api, session = client()

    result = api.batch_quotes([])

    assert result.quotes == ()
    assert session.calls == []

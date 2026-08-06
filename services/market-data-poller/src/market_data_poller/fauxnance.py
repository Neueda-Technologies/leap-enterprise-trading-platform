"""Fauxnance batch quotes client.

The batch endpoint is the only one this service calls. ``GET /quotes?symbols=A,B,C`` takes up to 25
symbols and costs one request against the daily quota, however many symbols are in it. Calling
``GET /quotes/{symbol}`` once per symbol returns the same data for eight times the quota.

The response reports per-symbol outcomes: an entry carries either a ``quote`` or an ``error``. One
bad symbol therefore does not fail the call, and this client does not let it fail the poll either.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any, Iterable, Sequence

import requests

log = logging.getLogger(__name__)


class FauxnanceError(RuntimeError):
    """The call failed in a way that may succeed on a later attempt."""


class QuotaExhaustedError(FauxnanceError):
    """HTTP 429. The daily quota is spent and does not refill until 00:00 UTC."""


@dataclass(frozen=True)
class Quote:
    """One quote, in the shape the ``market-data`` payload needs.

    Prices are held as the numbers ``json`` parsed, and no arithmetic is done on them anywhere in
    this service. The platform rule against floating-point money applies to the cash ledger in
    Postgres, which this service never touches.
    """

    symbol: str
    price: float
    currency: str | None
    change: float | None
    change_percent: float | None
    previous_close: float | None
    market_state: str
    stale: bool
    as_of: str | None


@dataclass(frozen=True)
class BatchResult:
    quotes: tuple[Quote, ...]
    failed_symbols: tuple[str, ...]


class FauxnanceClient:
    """A thin wrapper over one endpoint. Injectable session so that tests never open a socket."""

    def __init__(
        self,
        base_url: str,
        api_key: str,
        timeout_seconds: float = 5.0,
        session: Any | None = None,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout_seconds
        self._session = session if session is not None else requests.Session()
        self._session.headers.update({"X-Api-Key": api_key, "Accept": "application/json"})

    def batch_quotes(self, symbols: Sequence[str]) -> BatchResult:
        """Fetches up to 25 symbols in one request.

        :raises QuotaExhaustedError: on 429
        :raises FauxnanceError: on any other failure of the call itself
        """
        if not symbols:
            return BatchResult(quotes=(), failed_symbols=())

        url = f"{self._base_url}/quotes"
        try:
            response = self._session.get(
                url, params={"symbols": ",".join(symbols)}, timeout=self._timeout
            )
        except Exception as exc:  # requests raises a family of transport errors
            raise FauxnanceError(f"Quote request failed: {exc}") from exc

        if response.status_code == 429:
            raise QuotaExhaustedError("Daily Fauxnance quota exhausted. Check GET /usage.")
        if response.status_code >= 400:
            raise FauxnanceError(
                f"Fauxnance returned {response.status_code} for {len(symbols)} symbols"
            )

        try:
            body = response.json()
        except ValueError as exc:
            raise FauxnanceError("Fauxnance returned a body that is not JSON") from exc

        return _parse_batch(body, symbols)


def _parse_batch(body: Any, requested: Sequence[str]) -> BatchResult:
    """Turns the response body into quotes, skipping anything unusable.

    A malformed entry is logged and dropped. Raising here would throw away the quotes that did
    parse, which is the opposite of what a poller should do with one bad symbol.
    """
    entries = _entries(body)
    quotes: list[Quote] = []
    failed: list[str] = []

    for entry in entries:
        symbol = entry.get("symbol") if isinstance(entry, dict) else None
        if not symbol:
            log.warning("Dropping a batch entry with no symbol", extra={"entry": entry})
            continue
        if "error" in entry and entry.get("error"):
            log.warning(
                "Fauxnance returned an error for a symbol",
                extra={"symbol": symbol, "error": entry["error"]},
            )
            failed.append(symbol)
            continue
        quote = _parse_quote(symbol, entry)
        if quote is None:
            failed.append(symbol)
            continue
        quotes.append(quote)

    returned = {quote.symbol for quote in quotes} | set(failed)
    for symbol in requested:
        if symbol not in returned:
            log.warning("Fauxnance returned no entry for a requested symbol",
                        extra={"symbol": symbol})
            failed.append(symbol)

    return BatchResult(quotes=tuple(quotes), failed_symbols=tuple(failed))


def _entries(body: Any) -> Iterable[Any]:
    if isinstance(body, dict):
        data = body.get("data")
        if isinstance(data, dict) and isinstance(data.get("quotes"), list):
            return data["quotes"]
    log.warning("Fauxnance batch response had no data.quotes array")
    return ()


def _parse_quote(symbol: str, entry: dict[str, Any]) -> Quote | None:
    quote = entry.get("quote")
    if not isinstance(quote, dict):
        log.warning("Batch entry carries neither a quote nor an error",
                    extra={"symbol": symbol})
        return None

    price = quote.get("price")
    if not isinstance(price, (int, float)) or isinstance(price, bool):
        log.warning("Dropping a quote with no usable price",
                    extra={"symbol": symbol, "price": price})
        return None

    return Quote(
        symbol=symbol,
        price=price,
        currency=quote.get("currency"),
        change=quote.get("change"),
        change_percent=quote.get("changePercent"),
        previous_close=quote.get("previousClose"),
        # marketState is passed through untouched. The poller does not decide what an open market
        # is; Fauxnance does, and a consumer that disagrees can read the field for itself.
        market_state=quote.get("marketState") or "unknown",
        # Staleness sits on the batch entry, beside the quote, not inside it.
        stale=bool(entry.get("stale", False)),
        as_of=quote.get("asOf"),
    )

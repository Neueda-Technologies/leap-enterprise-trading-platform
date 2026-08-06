"""A small client for the Fauxnance API's candle endpoint.

Fauxnance serves end-of-day candles and delayed quotes, never a stream
(docs/DECISIONS.md, decision 2). The ETL's only use of it is
`GET /candles/{symbol}?from=&to=`, pulled during extract to support the
reasonableness check in `analytics.etl.validate` and to satisfy the Sprint 4
acceptance criterion that candles are pulled with the key read from the
environment.

Retries with backoff live here rather than in the caller, because a quota
error and a network blip are the client's problem to absorb, not the
pipeline's.
"""

from __future__ import annotations

import logging
import random
import time
from dataclasses import dataclass
from datetime import date

import requests

logger = logging.getLogger(__name__)

# Status codes worth retrying. 429 is the Fauxnance quota response
# (docs/DECISIONS.md, decision 2); 5xx is the server's problem, not the
# request's. Any other 4xx means the request itself is wrong and retrying it
# would just repeat the mistake.
_RETRYABLE_STATUS_CODES = frozenset({429, 500, 502, 503, 504})


class FauxnanceError(RuntimeError):
    """Raised when a Fauxnance request fails after every retry is exhausted."""


@dataclass(frozen=True)
class Candle:
    symbol: str
    trade_date: date
    open: float
    high: float
    low: float
    close: float
    volume: int


class FauxnanceClient:
    """Thin HTTP client. Holds no state beyond the session and configuration."""

    def __init__(
        self,
        base_url: str,
        api_key: str | None,
        timeout_seconds: float = 10.0,
        max_retries: int = 4,
        session: requests.Session | None = None,
        sleep: callable = time.sleep,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._api_key = api_key
        self._timeout_seconds = timeout_seconds
        self._max_retries = max_retries
        self._session = session or requests.Session()
        self._sleep = sleep

    def get_candles(self, symbol: str, from_date: date, to_date: date) -> list[Candle]:
        """Fetch EOD candles for `symbol` over `[from_date, to_date]`, inclusive.

        Returns an empty list if Fauxnance has no candles for the range
        (a quiet trading day or a symbol added after the range started),
        rather than treating an empty envelope as an error.
        """
        params = {"from": from_date.isoformat(), "to": to_date.isoformat()}
        payload = self._get(f"/candles/{symbol}", params=params)
        candles = payload.get("data", {}).get("candles", [])
        return [self._parse_candle(symbol, raw) for raw in candles]

    @staticmethod
    def _parse_candle(symbol: str, raw: dict) -> Candle:
        return Candle(
            symbol=symbol,
            trade_date=date.fromisoformat(raw["date"]),
            open=float(raw["open"]),
            high=float(raw["high"]),
            low=float(raw["low"]),
            close=float(raw["close"]),
            volume=int(raw.get("volume", 0)),
        )

    def _get(self, path: str, params: dict) -> dict:
        url = f"{self._base_url}{path}"
        headers = {"X-Api-Key": self._api_key} if self._api_key else {}

        last_error: Exception | None = None
        for attempt in range(self._max_retries + 1):
            try:
                response = self._session.get(
                    url, params=params, headers=headers, timeout=self._timeout_seconds
                )
            except requests.RequestException as exc:
                last_error = exc
                self._wait_before_retry(attempt, reason=str(exc))
                continue

            if response.status_code == 200:
                return response.json()

            if response.status_code in _RETRYABLE_STATUS_CODES and attempt < self._max_retries:
                self._wait_before_retry(
                    attempt, reason=f"HTTP {response.status_code}", response=response
                )
                continue

            raise FauxnanceError(
                f"GET {url} failed with HTTP {response.status_code}: {response.text[:500]}"
            )

        raise FauxnanceError(f"GET {url} failed after {self._max_retries} retries: {last_error}")

    def _wait_before_retry(
        self, attempt: int, reason: str, response: requests.Response | None = None
    ) -> None:
        retry_after = None
        if response is not None:
            retry_after = response.headers.get("Retry-After")

        if retry_after is not None:
            delay = float(retry_after)
        else:
            # Exponential backoff with full jitter: base 0.5s, doubling each
            # attempt, capped at 8s so a flaky run does not stall a batch.
            delay = min(8.0, 0.5 * (2**attempt)) * random.random()

        logger.warning(
            "Fauxnance request failed (%s), attempt %d of %d, retrying in %.2fs",
            reason,
            attempt + 1,
            self._max_retries,
            delay,
        )
        self._sleep(delay)

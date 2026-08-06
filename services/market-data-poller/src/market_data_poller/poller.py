"""The poll loop.

Fauxnance serves delayed quotes over HTTP and has no stream. This loop is what turns that into one,
and it is the reason the Sprint 10 extensions that consume ``market-data`` have anything to read.

Two rules shape the code. The loop never dies on a bad symbol or a failed request, because a poller
that exits on the first 503 is a poller nobody notices has stopped. And every HTTP call is counted
against the daily quota before it is made, because 2000 requests is not many.
"""

from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Callable, Iterator, Sequence

from .config import MAX_BATCH_SIZE, Settings
from .fauxnance import FauxnanceError, QuotaExhaustedError
from .quota import RequestBudget

log = logging.getLogger(__name__)


class _BudgetSpent(Exception):
    """Internal signal: stop calling Fauxnance for the rest of this cycle."""


@dataclass(frozen=True)
class PollResult:
    published: int
    failed_symbols: tuple[str, ...]
    requests_used: int
    quota_blocked: bool


class MarketDataPoller:
    """Polls, publishes, and keeps going."""

    def __init__(
        self,
        settings: Settings,
        client: Any,
        publisher: Any,
        budget: RequestBudget,
        sleep: Callable[[float], Any] | None = None,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._settings = settings
        self._client = client
        self._publisher = publisher
        self._budget = budget
        self._sleep = sleep or time.sleep
        self._now = now or (lambda: datetime.now(tz=timezone.utc))
        self._last_poll_at: datetime | None = None
        self._last_success_at: datetime | None = None
        self._published_total = 0

    def poll_once(self) -> PollResult:
        """One cycle: every symbol, in batches of at most 25."""
        used_before = self._budget.used()
        published = 0
        failed: list[str] = []
        quota_blocked = False

        for chunk in batches(self._settings.symbols, MAX_BATCH_SIZE):
            try:
                result = self._fetch(chunk)
            except _BudgetSpent:
                quota_blocked = True
                failed.extend(chunk)
                break
            except FauxnanceError as exc:
                log.error(
                    "Giving up on a batch for this cycle",
                    extra={"symbols": list(chunk), "error": str(exc)},
                )
                failed.extend(chunk)
                continue

            failed.extend(result.failed_symbols)
            for quote in result.quotes:
                try:
                    self._publisher.publish(quote)
                    published += 1
                except Exception:  # a broker problem must not lose the other symbols
                    log.exception("Could not publish a quote", extra={"symbol": quote.symbol})
                    failed.append(quote.symbol)

        self._last_poll_at = self._now()
        self._published_total += published
        if published:
            self._last_success_at = self._last_poll_at

        requests_used = self._budget.used() - used_before
        log.info(
            "Poll cycle complete",
            extra={
                "published": published,
                "failed": failed,
                "requests_used": requests_used,
                "requests_remaining_today": self._budget.remaining(),
            },
        )
        return PollResult(
            published=published,
            failed_symbols=tuple(failed),
            requests_used=requests_used,
            quota_blocked=quota_blocked,
        )

    def run(self, stop_event: threading.Event) -> None:
        """Polls until the event is set. Never raises."""
        self._log_start()
        while not stop_event.is_set():
            started = time.monotonic()
            try:
                self.poll_once()
            except Exception:
                # Anything not already handled inside poll_once. The loop survives it, because a
                # market-data feed that stops without exiting is the failure nobody sees.
                log.exception("Poll cycle failed")
            remaining = self._settings.poll_interval_seconds - (time.monotonic() - started)
            if stop_event.wait(max(0.0, remaining)):
                break
        log.info("Poller stopping, flushing the producer")
        try:
            self._publisher.flush(10.0)
        except Exception:
            log.exception("Producer flush failed during shutdown")

    def state(self) -> dict[str, Any]:
        """The health endpoint's view. Kept small and free of anything secret."""
        status = "ok" if self._last_success_at is not None else "starting"
        if self._last_success_at is not None:
            staleness = (self._now() - self._last_success_at).total_seconds()
            if staleness > self._settings.poll_interval_seconds * 3:
                status = "degraded"
        return {
            "status": status,
            "symbols": list(self._settings.symbols),
            "pollIntervalSeconds": self._settings.poll_interval_seconds,
            "lastPollAt": _iso(self._last_poll_at),
            "lastSuccessAt": _iso(self._last_success_at),
            "quotesPublished": self._published_total,
            "requestsUsedToday": self._budget.used(),
            "requestsRemainingToday": self._budget.remaining(),
        }

    def _fetch(self, chunk: tuple[str, ...]):
        """One batch, with retries. Every attempt costs a quota unit, so attempts are bounded."""
        delay = self._settings.backoff_initial_seconds
        for attempt in range(1, self._settings.max_attempts + 1):
            if not self._budget.try_consume():
                log.error(
                    "Daily request budget spent. Not calling Fauxnance again today.",
                    extra={"limit": self._budget.limit, "symbols": list(chunk)},
                )
                raise _BudgetSpent()
            try:
                return self._client.batch_quotes(chunk)
            except QuotaExhaustedError as exc:
                self._budget.exhaust()
                log.error("Fauxnance rejected the call for quota", extra={"error": str(exc)})
                raise _BudgetSpent() from exc
            except FauxnanceError as exc:
                log.warning(
                    "Batch quote request failed",
                    extra={
                        "attempt": attempt,
                        "of": self._settings.max_attempts,
                        "symbols": list(chunk),
                        "error": str(exc),
                    },
                )
                if attempt == self._settings.max_attempts:
                    raise
                self._sleep(delay)
                delay = min(delay * 2, self._settings.backoff_max_seconds)
        raise FauxnanceError("Unreachable retry state")

    def _log_start(self) -> None:
        per_poll = self._settings.requests_per_poll
        interval = self._settings.poll_interval_seconds
        polls_per_day = 86400.0 / interval
        log.info(
            "Poller started",
            extra={
                "symbols": list(self._settings.symbols),
                "poll_interval_seconds": interval,
                "requests_per_poll": per_poll,
                "requests_per_day_if_run_continuously": round(polls_per_day * per_poll),
                "daily_budget": self._budget.limit,
                "hours_of_polling_the_budget_covers": round(
                    self._budget.limit / (per_poll * 3600.0 / interval), 1
                ),
            },
        )


def batches(items: Sequence[str], size: int) -> Iterator[tuple[str, ...]]:
    """Splits a symbol list into groups no larger than the endpoint accepts."""
    for start in range(0, len(items), size):
        yield tuple(items[start:start + size])


def _iso(moment: datetime | None) -> str | None:
    if moment is None:
        return None
    return moment.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

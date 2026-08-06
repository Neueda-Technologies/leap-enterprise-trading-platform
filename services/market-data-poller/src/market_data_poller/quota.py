"""Client-side accounting for the Fauxnance daily quota.

Fauxnance enforces the quota itself and answers 429 when it is spent. This class exists so that the
poller knows before it makes the call, for two reasons. A 429 costs a round trip and tells the team
nothing they can act on at three in the afternoon. And a poller that keeps calling after the quota
is gone fills the log with failures that hide any real problem.

The counter resets at 00:00 UTC, which is when Fauxnance resets it.
"""

from __future__ import annotations

import logging
import threading
from datetime import date, datetime, timezone
from typing import Callable

log = logging.getLogger(__name__)


class RequestBudget:
    """A thread-safe counter of requests spent today."""

    def __init__(self, limit: int, now: Callable[[], datetime] | None = None) -> None:
        self._limit = limit
        self._now = now or (lambda: datetime.now(tz=timezone.utc))
        self._lock = threading.Lock()
        self._day: date = self._now().date()
        self._used = 0

    @property
    def limit(self) -> int:
        return self._limit

    def used(self) -> int:
        with self._lock:
            self._roll_over()
            return self._used

    def remaining(self) -> int:
        with self._lock:
            self._roll_over()
            return max(0, self._limit - self._used)

    def try_consume(self, amount: int = 1) -> bool:
        """Reserves ``amount`` requests, or returns False when the budget cannot cover them."""
        with self._lock:
            self._roll_over()
            if self._used + amount > self._limit:
                return False
            self._used += amount
            return True

    def exhaust(self) -> None:
        """Marks the budget as spent, for when Fauxnance answers 429 before the counter did.

        The two counters can disagree. The key is per student, not per process, and a team running
        the poller and the executor against one key spends the same quota twice over.
        """
        with self._lock:
            self._roll_over()
            if self._used < self._limit:
                log.warning(
                    "Fauxnance reported the quota spent before the local counter did",
                    extra={"local_used": self._used, "limit": self._limit},
                )
            self._used = self._limit

    def _roll_over(self) -> None:
        today = self._now().date()
        if today != self._day:
            log.info("Daily request budget reset",
                     extra={"previous_day": str(self._day), "used": self._used})
            self._day = today
            self._used = 0

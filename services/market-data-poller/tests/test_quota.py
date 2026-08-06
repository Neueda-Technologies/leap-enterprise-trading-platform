from __future__ import annotations

from datetime import datetime, timedelta, timezone

from market_data_poller.quota import RequestBudget


class MovableClock:
    def __init__(self, start: datetime):
        self.now = start

    def __call__(self) -> datetime:
        return self.now

    def advance(self, delta: timedelta) -> None:
        self.now += delta


def test_consuming_reduces_what_is_left():
    budget = RequestBudget(10)

    assert budget.try_consume() is True
    assert budget.used() == 1
    assert budget.remaining() == 9


def test_the_budget_refuses_the_request_that_would_cross_the_limit():
    budget = RequestBudget(2)

    assert budget.try_consume() is True
    assert budget.try_consume() is True
    assert budget.try_consume() is False
    assert budget.remaining() == 0


def test_a_multi_unit_reservation_is_all_or_nothing():
    budget = RequestBudget(3)

    assert budget.try_consume(2) is True
    assert budget.try_consume(2) is False
    assert budget.used() == 2


def test_exhaust_marks_the_whole_budget_spent():
    budget = RequestBudget(100)
    budget.try_consume()

    budget.exhaust()

    assert budget.remaining() == 0
    assert budget.try_consume() is False


def test_the_counter_resets_when_the_utc_day_changes():
    clock = MovableClock(datetime(2026, 9, 28, 23, 59, tzinfo=timezone.utc))
    budget = RequestBudget(5, now=clock)
    for _ in range(5):
        budget.try_consume()
    assert budget.remaining() == 0

    clock.advance(timedelta(minutes=2))

    assert budget.remaining() == 5
    assert budget.try_consume() is True


def test_the_counter_does_not_reset_within_the_same_day():
    clock = MovableClock(datetime(2026, 9, 28, 0, 1, tzinfo=timezone.utc))
    budget = RequestBudget(5, now=clock)
    budget.try_consume()

    clock.advance(timedelta(hours=12))

    assert budget.used() == 1

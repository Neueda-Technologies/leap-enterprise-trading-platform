from __future__ import annotations

import threading

from conftest import FakeClient, FakePublisher, quote, settings

from market_data_poller.fauxnance import BatchResult, FauxnanceError, QuotaExhaustedError
from market_data_poller.poller import MarketDataPoller, batches
from market_data_poller.quota import RequestBudget


class RecordingSleep:
    def __init__(self):
        self.slept: list[float] = []

    def __call__(self, seconds: float) -> None:
        self.slept.append(seconds)


def build(client: FakeClient, publisher: FakePublisher, **overrides):
    config = settings(**overrides)
    budget = RequestBudget(config.daily_request_budget)
    sleeper = RecordingSleep()
    poller = MarketDataPoller(config, client, publisher, budget, sleep=sleeper)
    return poller, budget, sleeper


def test_a_cycle_publishes_one_message_per_symbol_for_one_request():
    client = FakeClient()
    publisher = FakePublisher()
    poller, budget, _ = build(client, publisher)

    result = poller.poll_once()

    assert result.published == 2
    assert [q.symbol for q in publisher.published] == ["AAPL", "MSFT"]
    assert budget.used() == 1
    assert result.requests_used == 1


def test_more_than_twenty_five_symbols_becomes_two_requests():
    symbols = tuple(f"SYM{i}" for i in range(30))
    client = FakeClient()
    publisher = FakePublisher()
    poller, budget, _ = build(client, publisher, symbols=symbols)

    poller.poll_once()

    assert [len(call) for call in client.calls] == [25, 5]
    assert budget.used() == 2


def test_a_transient_failure_is_retried_with_exponential_backoff():
    client = FakeClient(
        [
            FauxnanceError("503"),
            FauxnanceError("503"),
            BatchResult(quotes=(quote("AAPL"), quote("MSFT")), failed_symbols=()),
        ]
    )
    publisher = FakePublisher()
    poller, budget, sleeper = build(client, publisher, backoff_initial_seconds=1.0)

    result = poller.poll_once()

    assert result.published == 2
    assert sleeper.slept == [1.0, 2.0]
    # Every attempt is a request, and every request is counted.
    assert budget.used() == 3


def test_a_failure_that_outlives_the_retry_budget_does_not_stop_the_process():
    client = FakeClient([FauxnanceError("503")] * 3)
    publisher = FakePublisher()
    poller, _, _ = build(client, publisher, max_attempts=3)

    result = poller.poll_once()

    assert result.published == 0
    assert set(result.failed_symbols) == {"AAPL", "MSFT"}


def test_a_failed_batch_does_not_stop_the_next_batch():
    symbols = tuple(f"SYM{i}" for i in range(30))
    client = FakeClient(
        [FauxnanceError("503")] * 3
        + [BatchResult(quotes=(quote("SYM25"),), failed_symbols=())]
    )
    publisher = FakePublisher()
    poller, _, _ = build(client, publisher, symbols=symbols, max_attempts=3)

    result = poller.poll_once()

    assert result.published == 1
    assert len(client.calls) == 4


def test_a_symbol_error_inside_a_good_batch_is_recorded_not_raised():
    client = FakeClient([BatchResult(quotes=(quote("AAPL"),), failed_symbols=("MSFT",))])
    publisher = FakePublisher()
    poller, _, _ = build(client, publisher)

    result = poller.poll_once()

    assert result.published == 1
    assert result.failed_symbols == ("MSFT",)


def test_a_broker_failure_on_one_symbol_does_not_lose_the_others():
    client = FakeClient()
    publisher = FakePublisher(fail_for={"AAPL"})
    poller, _, _ = build(client, publisher)

    result = poller.poll_once()

    assert [q.symbol for q in publisher.published] == ["MSFT"]
    assert result.failed_symbols == ("AAPL",)


def test_a_spent_budget_stops_the_calls_before_they_are_made():
    client = FakeClient()
    publisher = FakePublisher()
    poller, budget, _ = build(client, publisher, daily_request_budget=1)

    first = poller.poll_once()
    second = poller.poll_once()

    assert first.requests_used == 1
    assert second.quota_blocked is True
    assert len(client.calls) == 1


def test_a_quota_rejection_from_fauxnance_spends_the_local_budget_too():
    client = FakeClient([QuotaExhaustedError("429")])
    publisher = FakePublisher()
    poller, budget, _ = build(client, publisher)

    result = poller.poll_once()

    assert result.quota_blocked is True
    assert budget.remaining() == 0


def test_the_loop_stops_when_the_event_is_set_and_flushes_on_the_way_out():
    stop = threading.Event()

    class StoppingPublisher(FakePublisher):
        def publish(self, quote_to_publish, event_time=None):
            super().publish(quote_to_publish, event_time)
            stop.set()

    publisher = StoppingPublisher()
    poller, _, _ = build(FakeClient(), publisher, poll_interval_seconds=0.01)

    poller.run(stop)

    assert [q.symbol for q in publisher.published] == ["AAPL", "MSFT"]
    assert publisher.flushed == 1


def test_the_loop_survives_an_unexpected_failure():
    class ExplodingPublisher(FakePublisher):
        def publish(self, quote_to_publish, event_time=None):
            raise RuntimeError("boom")

    client = FakeClient()
    poller, _, _ = build(client, ExplodingPublisher(), poll_interval_seconds=0.01)
    stop = threading.Event()
    stop.set()

    poller.run(stop)  # returns rather than raising


def test_health_state_reports_progress_without_leaking_the_key():
    client = FakeClient()
    publisher = FakePublisher()
    poller, _, _ = build(client, publisher)

    before = poller.state()
    poller.poll_once()
    after = poller.state()

    assert before["status"] == "starting"
    assert after["status"] == "ok"
    assert after["quotesPublished"] == 2
    assert after["requestsRemainingToday"] == 1999
    assert "apiKey" not in after and "test-key" not in str(after)


def test_batches_never_exceed_the_endpoint_limit():
    assert list(batches(tuple(str(i) for i in range(26)), 25)) == [
        tuple(str(i) for i in range(25)),
        ("25",),
    ]

"""Entry point. Wires the parts together and shuts them down in the right order."""

from __future__ import annotations

import logging
import os
import signal
import sys
import threading

from .config import ConfigurationError, Settings
from .fauxnance import FauxnanceClient
from .health import HealthServer
from .logging_setup import configure_logging
from .poller import MarketDataPoller
from .publisher import QuotePublisher
from .quota import RequestBudget

log = logging.getLogger(__name__)


def main() -> int:
    # Logging is configured before the settings are read so that a configuration warning comes out
    # in the same format as everything else.
    configure_logging(os.environ.get("LOG_LEVEL", "INFO"))

    try:
        settings = Settings.from_env()
    except ConfigurationError as exc:
        log.error("Cannot start", extra={"reason": str(exc)})
        return 2

    stop_event = threading.Event()
    _install_signal_handlers(stop_event)

    client = FauxnanceClient(
        base_url=settings.base_url,
        api_key=settings.api_key,
        timeout_seconds=settings.request_timeout_seconds,
    )
    publisher = QuotePublisher.create(settings.bootstrap_servers, settings.topic)
    budget = RequestBudget(settings.daily_request_budget)
    poller = MarketDataPoller(settings, client, publisher, budget, sleep=stop_event.wait)

    health = HealthServer(settings.health_port, poller.state)
    health.start()
    try:
        poller.run(stop_event)
    finally:
        health.stop()
        publisher.close()
    log.info("Shutdown complete")
    return 0


def _install_signal_handlers(stop_event: threading.Event) -> None:
    """Turns SIGTERM and SIGINT into a request to finish the current cycle and stop.

    ``docker stop`` sends SIGTERM and then waits. A process that ignores it is killed ten seconds
    later, part way through a publish.
    """

    def handle(signum: int, _frame: object) -> None:
        log.info("Signal received, shutting down", extra={"signal": signal.Signals(signum).name})
        stop_event.set()

    signal.signal(signal.SIGTERM, handle)
    signal.signal(signal.SIGINT, handle)


if __name__ == "__main__":
    sys.exit(main())

"""Configuration, read once from the environment.

Single responsibility: turn environment variables into a value the rest of the
service can be handed. Nothing else in the package reads `os.environ`, because
a module that reads the environment where it is used cannot be tested without
setting the environment first.

What has to be configurable rather than written into the code:

    FAUXNANCE_API_KEY          required, no default, never a literal
    FAUXNANCE_BASE_URL         the programme's base URL
    MARKET_DATA_SYMBOLS        the symbols to poll, comma separated
    KAFKA_BOOTSTRAP_SERVERS    kafka:29092 in compose, localhost:9092 on the host
    MARKET_DATA_TOPIC          the topic name from contracts/kafka-topics.md
    POLL_INTERVAL_SECONDS      seconds between cycles

The symbol list is configuration and not a constant in the source. A team that
hard-codes it has to rebuild an image to watch a different instrument, and the
Sprint 10 watchlist extension has no way to influence what is polled.

Two decisions belong here rather than in the poll loop. What the service does
when the key is absent, which should be to refuse to start rather than to fail
every cycle in the same way for ever. And what the shortest interval it will
accept is, enforced in code: below roughly fifteen seconds no configuration of
this service survives even a half-day session, and the quotes are delayed
anyway, so polling faster than the data changes buys nothing but requests.

A bad value names itself. `POLL_INTERVAL_SECONDS=thirty` should say which
variable was wrong, not raise a ValueError from inside a call three frames
down.
"""

"""Entry point: `python -m market_data_poller`, and the console script.

Single responsibility: read the configuration, build the client, the budget and
the publisher, hand them to the loop, and translate a shutdown signal into a
clean exit.

Keep it thin. Everything that happens here is untestable without starting the
process, so the less that happens here the more of the service is testable.

`main()` returns an exit status. Zero when the service was asked to stop and
stopped. Non-zero when it could not start, for example because no Fauxnance key
was set.
"""

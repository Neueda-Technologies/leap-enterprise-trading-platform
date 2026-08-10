"""The market-data poller.

The curriculum promises a real-time price stream. Fauxnance does not have one:
it serves end-of-day candles and delayed quotes over HTTP, with no WebSocket
and no server-sent events. This service is what manufactures the stream. It
calls the batch quotes endpoint on an interval and publishes each quote to the
`market-data` topic.

Without it that topic is empty, and every Sprint 10 extension that reads prices
has nothing to consume.

It is also the smallest complete producer in the platform: one responsibility,
one topic, no database. That makes it the right place to see what a Kafka
producer configuration actually costs.

Modules ship as docstrings. What goes in each one is stated; the code is yours.
"""

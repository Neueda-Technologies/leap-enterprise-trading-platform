"""Publishing quotes to the market-data topic.

Single responsibility: turn a quote into the envelope `contracts/kafka-topics.md`
specifies and send it. It fetches nothing.

One message per symbol, keyed by the symbol. Never one message per batch.
Batching the HTTP call is a quota optimisation and it is correct. Batching the
Kafka message puts several symbols behind one key, which destroys the
per-symbol ordering the topic contract promises and stops a consumer filtering
to the instruments it cares about.

The envelope is the platform's five fields plus a payload, identical on all
three topics so that one deserialiser and one dead-letter handler cover
everything. `source` is `market-poller`.

`eventTime` and `quoteAsOf` are different timestamps and the difference is the
point. `eventTime` is when this process published. `quoteAsOf` is when
Fauxnance observed the price. Fauxnance serves delayed quotes, so a strategy
service acting on `eventTime` is acting on a price older than it thinks. Setting
`quoteAsOf` to the current time because it was easier is the most common error
in this service and it is invisible until Sprint 10.

Pass the producer in rather than constructing it here, and import the Kafka
library inside the construction rather than at module scope. Both make it
possible to test the message shape without a broker anywhere on the machine.
"""

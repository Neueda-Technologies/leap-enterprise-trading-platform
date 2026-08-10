/**
 * The consumer: everything that knows a message arrived.
 *
 * <p>Single responsibility: read a record from {@code orders}, turn its bytes into something the
 * execution layer can act on, hand it over, and then decide what to do with the offset and with a
 * message that could not be handled.
 *
 * <p>This is the layer that owns the two failure classes. A message that will never succeed, such
 * as one that fails to deserialise or names an order that is not in the database, goes to the
 * dead-letter topic on the first attempt. A message that will succeed later, such as one that hit a
 * database that was briefly unreachable, is retried with backoff and dead-lettered only when the
 * retry budget is spent. Retrying a poison message for ever blocks the partition, and every account
 * keyed to that partition stops trading.
 *
 * <p>Deserialisation tolerates fields it does not recognise. The envelope in
 * {@code contracts/kafka-topics.md} may gain optional fields without a version bump, and a consumer
 * that fails on an unknown field turns an additive change into an outage.
 *
 * <p>Nothing in this package decides whether an order fills.
 */
package com.tradingplatform.executor.consumer;

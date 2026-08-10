/**
 * Publishing: the outcome, onto {@code trade-events}.
 *
 * <p>Single responsibility: build the envelope and the payload that {@code contracts/kafka-topics.md}
 * specifies for a lifecycle event, and send it keyed by {@code accountId} so that one account's
 * events stay in order.
 *
 * <p>A rejection is an event. Publish it. The blotter, the notifications extension and the
 * analytics estate all need to know that an order failed, and a consumer that only ever sees fills
 * reports a fill rate of 100 per cent.
 *
 * <p>Three payload fields exist for consumers rather than for this service:
 * {@code cashDelta}, {@code positionQuantityAfter} and {@code averageCostAfter}. They let a
 * downstream service maintain its own view of a portfolio without querying the trading database,
 * which is what makes the Sprint 10 Portfolio extension possible. Populate them from what the
 * transaction actually wrote, not from what it intended to write.
 *
 * <p>Publish after the commit and acknowledge the offset after the publish. Publishing first risks
 * an event for a transaction that rolled back, and nothing can undo that. Acknowledging first risks
 * an order that settled and told nobody, and a redelivery recovers from it.
 */
package com.tradingplatform.executor.publish;

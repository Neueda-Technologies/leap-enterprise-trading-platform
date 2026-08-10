/**
 * Configuration: the consumer, the producer, and the values that differ between a laptop and a
 * container.
 *
 * <p>Single responsibility: turn environment variables into wired beans. No decision about an order
 * is taken here.
 *
 * <p>Four settings in this package are assessed rather than incidental. The consumer group
 * identifier, which is the same one every instance of this service uses and which no other service
 * shares. Automatic offset committing, which has to be off, because the offset is committed after
 * the work rather than after the poll. The producer's acknowledgement and idempotence settings,
 * which the topic contract fixes. The dead-letter destination, which the contract names as
 * {@code <topic>.DLT} and which most frameworks default to something else.
 *
 * <p>Nothing sensitive carries a default. A service that starts without its Fauxnance key and
 * rejects every order is easier to diagnose than one that starts with a key somebody committed.
 */
package com.tradingplatform.executor.config;

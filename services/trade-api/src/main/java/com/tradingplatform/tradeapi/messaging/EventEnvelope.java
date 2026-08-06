package com.tradingplatform.tradeapi.messaging;

import java.time.Instant;
import java.util.UUID;

/**
 * The five-field envelope every message on every topic carries.
 *
 * <p>Identical on {@code orders}, {@code trade-events} and {@code market-data}, so that one
 * deserialiser and one dead-letter handler cover the whole platform. A consumer that has to know
 * which topic a message came from before it can read the metadata has lost that.
 *
 * <p>{@code eventId} is the consumer's idempotency key. The platform runs at-least-once, duplicates
 * happen, and a consumer with a side effect must be able to see the same {@code eventId} twice
 * without doing the work twice.
 *
 * <p>{@code eventTime} is when the producer created the event, not when a consumer read it. The
 * difference is invisible until something is slow, at which point it is the only way to tell a slow
 * producer from a slow consumer.
 *
 * <p>{@code schemaVersion} starts at 1 and increments only on a breaking change. Adding an optional
 * field is not breaking. Removing a field, renaming one or changing its type is. Consumers must
 * ignore fields they do not recognise, which is what lets a producer add one without a coordinated
 * release across six services.
 *
 * @param eventId       unique per message
 * @param eventType     discriminates the payload
 * @param eventTime     when the producer created the event, UTC
 * @param source        producing service
 * @param schemaVersion payload schema version
 * @param payload       topic-specific and event-type-specific body
 */
public record EventEnvelope<T>(
        String eventId,
        String eventType,
        Instant eventTime,
        String source,
        int schemaVersion,
        T payload) {

    /** This service, as it appears in the {@code source} field. */
    public static final String SOURCE_TRADE_API = "trade-api";

    /** Current payload schema version for both topics this service produces to. */
    public static final int CURRENT_SCHEMA_VERSION = 1;

    /** Wraps a payload produced by this service. */
    public static <T> EventEnvelope<T> from(String eventType, Instant eventTime, T payload) {
        return new EventEnvelope<>(
                UUID.randomUUID().toString(),
                eventType,
                eventTime,
                SOURCE_TRADE_API,
                CURRENT_SCHEMA_VERSION,
                payload);
    }
}

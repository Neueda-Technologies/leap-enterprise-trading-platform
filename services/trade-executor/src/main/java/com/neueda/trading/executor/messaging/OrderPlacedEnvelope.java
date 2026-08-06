package com.neueda.trading.executor.messaging;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * The five-field envelope every message on every topic carries, as consumed from {@code orders}.
 *
 * <p>Unknown fields are ignored on purpose. The contract allows a producer to add an optional field
 * without incrementing {@code schemaVersion}, and a consumer that fails on an unrecognised field
 * turns an additive change into an outage.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record OrderPlacedEnvelope(
        String eventId,
        String eventType,
        String eventTime,
        String source,
        Integer schemaVersion,
        OrderPlacedPayload payload) {

    public static final String ORDER_PLACED = "ORDER_PLACED";
}

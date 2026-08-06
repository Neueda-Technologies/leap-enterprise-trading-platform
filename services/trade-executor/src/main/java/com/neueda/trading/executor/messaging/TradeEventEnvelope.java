package com.neueda.trading.executor.messaging;

/**
 * The outbound envelope for {@code trade-events}. {@code source} is always {@code trade-executor}
 * and {@code schemaVersion} stays at 1 until a field is removed, renamed or retyped.
 */
public record TradeEventEnvelope(
        String eventId,
        String eventType,
        String eventTime,
        String source,
        int schemaVersion,
        TradeEventPayload payload) {

    public static final String SOURCE = "trade-executor";
    public static final int SCHEMA_VERSION = 1;
    public static final String ORDER_FILLED = "ORDER_FILLED";
    public static final String ORDER_REJECTED = "ORDER_REJECTED";
}

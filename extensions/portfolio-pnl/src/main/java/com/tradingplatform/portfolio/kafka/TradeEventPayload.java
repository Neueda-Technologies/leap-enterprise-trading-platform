package com.tradingplatform.portfolio.kafka;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

/**
 * The {@code trade-events} payload, per docs/contracts/kafka-topics.md. Only the
 * fields this service uses are modelled; the rest are ignored, per the "consumers must
 * ignore fields they do not recognise" rule.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record TradeEventPayload(
        UUID orderId,
        long accountId,
        String symbol,
        String side,
        int quantity,
        BigDecimal price,
        BigDecimal executedPrice,
        String status,
        String reason,
        BigDecimal cashDelta,
        Integer positionQuantityAfter,
        BigDecimal averageCostAfter,
        Instant executedOn) {
}

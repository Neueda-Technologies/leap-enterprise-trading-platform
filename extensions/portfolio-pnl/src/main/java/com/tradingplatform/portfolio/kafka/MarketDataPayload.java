package com.tradingplatform.portfolio.kafka;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import java.math.BigDecimal;
import java.time.Instant;

/** The {@code market-data} payload, per docs/contracts/kafka-topics.md. */
@JsonIgnoreProperties(ignoreUnknown = true)
public record MarketDataPayload(
        String symbol,
        BigDecimal price,
        String currency,
        BigDecimal change,
        BigDecimal changePercent,
        BigDecimal previousClose,
        String marketState,
        boolean stale,
        Instant quoteAsOf) {
}

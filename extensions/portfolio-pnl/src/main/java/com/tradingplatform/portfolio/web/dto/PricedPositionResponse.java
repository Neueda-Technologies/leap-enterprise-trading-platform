package com.tradingplatform.portfolio.web.dto;

import java.math.BigDecimal;
import java.time.Instant;

/** Matches {@code PricedPosition} in docs/contracts/portfolio-api.yaml. */
public record PricedPositionResponse(
        long accountId,
        String symbol,
        int quantity,
        BigDecimal averageCost,
        BigDecimal costBasis,
        BigDecimal lastPrice,
        BigDecimal marketValue,
        BigDecimal unrealisedPnl,
        BigDecimal unrealisedPnlPercent,
        String currency,
        Instant priceAsOf,
        boolean stale) {
}

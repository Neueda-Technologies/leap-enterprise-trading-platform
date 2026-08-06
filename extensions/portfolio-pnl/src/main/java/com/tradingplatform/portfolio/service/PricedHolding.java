package com.tradingplatform.portfolio.service;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * An intermediate, fully computed view of one position, before it is shaped into
 * either {@code PricedPosition} (native currency, one row per instrument) or folded
 * into {@code PortfolioSummary} (converted to the account's base currency). Kept
 * internal to the service layer so the two response shapes can diverge without the
 * pricing arithmetic being duplicated.
 */
record PricedHolding(
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
        boolean stale,
        boolean priced,
        BigDecimal costBasisInBaseCurrency,
        BigDecimal marketValueInBaseCurrency,
        boolean convertible) {
}

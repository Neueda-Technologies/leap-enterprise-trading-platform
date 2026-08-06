package com.tradingplatform.portfolio.web.dto;

import java.math.BigDecimal;
import java.time.Instant;

/** Matches {@code PortfolioSummary} in docs/contracts/portfolio-api.yaml. */
public record PortfolioSummaryResponse(
        long accountId,
        String baseCurrency,
        BigDecimal cashBalance,
        BigDecimal marketValue,
        BigDecimal costBasis,
        BigDecimal unrealisedPnl,
        BigDecimal unrealisedPnlPercent,
        BigDecimal realisedPnl,
        BigDecimal totalValue,
        int positionCount,
        boolean partial,
        Instant asOf) {
}

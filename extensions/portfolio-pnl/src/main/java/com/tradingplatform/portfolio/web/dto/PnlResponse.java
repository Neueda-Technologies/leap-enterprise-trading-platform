package com.tradingplatform.portfolio.web.dto;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

/** Matches {@code PnlResponse} in docs/contracts/portfolio-api.yaml. */
public record PnlResponse(
        long accountId,
        String baseCurrency,
        LocalDate from,
        LocalDate to,
        BigDecimal realisedPnl,
        BigDecimal unrealisedPnl,
        BigDecimal totalPnl,
        List<SymbolPnl> bySymbol,
        Instant asOf) {
}

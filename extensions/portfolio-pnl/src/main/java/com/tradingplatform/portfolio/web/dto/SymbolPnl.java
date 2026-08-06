package com.tradingplatform.portfolio.web.dto;

import java.math.BigDecimal;

/** Matches {@code SymbolPnl} in docs/contracts/portfolio-api.yaml. */
public record SymbolPnl(String symbol, BigDecimal realisedPnl, BigDecimal unrealisedPnl, BigDecimal totalPnl) {
}

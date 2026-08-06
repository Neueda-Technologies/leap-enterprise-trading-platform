package com.tradingplatform.portfolio.fauxnance;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * A priced quote for one symbol, from Fauxnance {@code GET /quotes} or from the
 * {@code market-data} topic used as a fallback. {@code stale} is true either because
 * Fauxnance flagged it, or because the quote is older than the freshness window this
 * service enforces.
 */
public record Quote(String symbol, BigDecimal price, String currency, Instant asOf, boolean stale) {
}

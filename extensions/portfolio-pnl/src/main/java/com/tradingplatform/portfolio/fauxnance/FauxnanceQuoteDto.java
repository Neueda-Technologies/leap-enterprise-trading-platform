package com.tradingplatform.portfolio.fauxnance;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import java.math.BigDecimal;
import java.time.Instant;

/**
 * One entry in the response of Fauxnance {@code GET /quotes?symbols=...}. The field
 * names mirror the {@code market-data} payload in docs/contracts/kafka-topics.md,
 * since both come from the same upstream quote. Unknown fields are ignored: this
 * service does not need every field Fauxnance returns, and a field Fauxnance adds
 * later must not break deserialisation.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record FauxnanceQuoteDto(
        String symbol, BigDecimal price, String currency, String marketState, boolean stale, Instant quoteAsOf) {
}

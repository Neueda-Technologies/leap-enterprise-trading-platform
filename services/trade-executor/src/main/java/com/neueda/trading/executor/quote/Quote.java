package com.neueda.trading.executor.quote;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * One delayed Fauxnance quote, reduced to the fields the executor uses.
 *
 * @param symbol      the instrument the quote is for
 * @param price       the quoted price, unrounded as Fauxnance returned it
 * @param currency    ISO 4217 code
 * @param asOf        when the price was observed, which is not when it was fetched
 * @param marketState one of open, closed, pre, post, unknown
 * @param stale       true when Fauxnance flagged the quote as past its freshness window
 */
public record Quote(
        String symbol,
        BigDecimal price,
        String currency,
        Instant asOf,
        String marketState,
        boolean stale) {
}

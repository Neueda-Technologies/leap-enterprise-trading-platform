package com.neueda.trading.executor.quote;

import java.util.Optional;

/**
 * Source of the price a fill is decided against.
 *
 * <p>An empty result means the executor has no usable price and has already exhausted whatever
 * retries it was going to make. Callers treat it as a business outcome, not as an error to throw:
 * the order is rejected with {@code PRICING_UNAVAILABLE}.
 */
public interface QuoteClient {

    Optional<Quote> quoteFor(String symbol);
}

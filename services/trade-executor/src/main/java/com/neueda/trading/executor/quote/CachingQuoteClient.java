package com.neueda.trading.executor.quote;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Holds each symbol's last quote for a short window so that a burst of orders on one instrument
 * costs one Fauxnance request rather than one per order.
 *
 * <p>The quota is 2000 requests per day per key and it is shared with the market-data poller. Ten
 * orders on AAPL arriving in the same second are ten requests without this class and one with it.
 * The window is deliberately short: a fill priced against a quote from a minute ago is not a fill
 * priced against the market.
 *
 * <p>Failures are never cached. A symbol that failed once must be retried on the next order, or one
 * transient Fauxnance error would reject every order on that symbol for the length of the window.
 */
public class CachingQuoteClient implements QuoteClient {

    private static final Logger log = LoggerFactory.getLogger(CachingQuoteClient.class);

    private final QuoteClient delegate;
    private final Duration maxAge;
    private final Clock clock;
    private final ConcurrentMap<String, CachedQuote> cache = new ConcurrentHashMap<>();

    public CachingQuoteClient(QuoteClient delegate, Duration maxAge, Clock clock) {
        this.delegate = delegate;
        this.maxAge = maxAge;
        this.clock = clock;
    }

    @Override
    public Optional<Quote> quoteFor(String symbol) {
        Instant now = clock.instant();
        CachedQuote cached = cache.get(symbol);
        if (cached != null && !cached.isOlderThan(maxAge, now)) {
            log.debug("Quote for {} served from cache, fetched at {}", symbol, cached.fetchedAt());
            return Optional.of(cached.quote());
        }
        Optional<Quote> fresh = delegate.quoteFor(symbol);
        fresh.ifPresent(quote -> cache.put(symbol, new CachedQuote(quote, now)));
        return fresh;
    }

    /** Visible for tests and for a future admin endpoint. */
    public void clear() {
        cache.clear();
    }

    private record CachedQuote(Quote quote, Instant fetchedAt) {

        boolean isOlderThan(Duration maxAge, Instant now) {
            return Duration.between(fetchedAt, now).compareTo(maxAge) >= 0;
        }
    }
}

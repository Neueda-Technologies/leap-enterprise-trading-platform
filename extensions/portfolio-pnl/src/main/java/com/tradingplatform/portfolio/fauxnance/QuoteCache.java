package com.tradingplatform.portfolio.fauxnance;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Component;

/**
 * Caches Fauxnance quotes for {@code fauxnance.quote-cache-ttl-seconds} (10 seconds by
 * default), so that three portfolio calls landing within the same window for the same
 * account cost one Fauxnance request rather than three.
 *
 * <p>The cache is per symbol, not per request, so two accounts holding the same
 * instrument share one cached quote. This matters for quota: the daily allowance is
 * 2000 requests platform-wide use of Fauxnance, not 2000 per account.
 *
 * <p>{@link Clock} is injected rather than read from {@link Instant#now()} directly so
 * that a test can advance time deterministically without a real 10-second sleep.
 */
@Component
public class QuoteCache {

    private record CacheEntry(Quote quote, Instant cachedAt) {
    }

    private final FauxnanceClient fauxnanceClient;
    private final Clock clock;
    private final Duration ttl;
    private final Map<String, CacheEntry> cache = new ConcurrentHashMap<>();

    public QuoteCache(FauxnanceClient fauxnanceClient, FauxnanceProperties properties) {
        this(fauxnanceClient, Clock.systemUTC(), Duration.ofSeconds(properties.quoteCacheTtlSeconds()));
    }

    /** Test-visible constructor: supply a fixed or advancing clock instead of the system clock. */
    QuoteCache(FauxnanceClient fauxnanceClient, Clock clock, Duration ttl) {
        this.fauxnanceClient = fauxnanceClient;
        this.clock = clock;
        this.ttl = ttl;
    }

    /**
     * Returns a quote per requested symbol that is either fresh in the cache or has
     * now been fetched. A symbol that Fauxnance could not price, and that has no
     * usable cached value, is absent from the result: the caller decides what an
     * absent price means for the response it is building.
     */
    public Map<String, Quote> getQuotes(Set<String> symbols) {
        Instant now = clock.instant();
        Map<String, Quote> result = new LinkedHashMap<>();
        List<String> toFetch = new ArrayList<>();

        for (String symbol : symbols) {
            CacheEntry entry = cache.get(symbol);
            if (entry != null && Duration.between(entry.cachedAt(), now).compareTo(ttl) < 0) {
                result.put(symbol, entry.quote());
            } else {
                toFetch.add(symbol);
            }
        }

        if (!toFetch.isEmpty()) {
            Map<String, Quote> fetched = fauxnanceClient.getQuotes(toFetch);
            for (String symbol : toFetch) {
                Quote fresh = fetched.get(symbol);
                if (fresh != null) {
                    cache.put(symbol, new CacheEntry(fresh, now));
                    result.put(symbol, fresh);
                    continue;
                }
                // Fauxnance did not price this symbol on this call, either because it
                // failed outright or because the symbol was absent from the response.
                // Fall back to whatever is already cached, market-data-primed or
                // merely expired, rather than reporting no price at all. It is served
                // marked stale, since by definition it is now outside the freshness
                // window this cache enforces.
                CacheEntry stale = cache.get(symbol);
                if (stale != null) {
                    Quote staleQuote = stale.quote().stale()
                            ? stale.quote()
                            : new Quote(
                                    stale.quote().symbol(),
                                    stale.quote().price(),
                                    stale.quote().currency(),
                                    stale.quote().asOf(),
                                    true);
                    result.put(symbol, staleQuote);
                }
            }
        }

        return result;
    }

    /**
     * Called by the {@code market-data} consumer to keep a last-known price warm even
     * when Fauxnance itself cannot be reached. A quote sourced this way is written
     * into the cache but the caller is responsible for marking it stale when it is far
     * enough behind the request time; this method does not overwrite a fresher
     * Fauxnance-sourced entry.
     */
    public void primeFromMarketData(Quote quote) {
        cache.merge(
                quote.symbol(),
                new CacheEntry(quote, clock.instant()),
                (existing, incoming) -> incoming.cachedAt().isAfter(existing.cachedAt()) ? incoming : existing);
    }

    int size() {
        return cache.size();
    }
}

package com.tradingplatform.portfolio.fauxnance;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Verifies the caching behaviour described in portfolio-api.yaml: batch the quote
 * call, and do not call Fauxnance again for a symbol still inside the freshness
 * window. A {@link MutableClock} advances time deterministically instead of sleeping
 * ten real seconds per test.
 */
class QuoteCacheTest {

    private static final Duration TTL = Duration.ofSeconds(10);

    private RecordingFauxnanceClient fauxnanceClient;
    private MutableClock clock;
    private QuoteCache quoteCache;

    @BeforeEach
    void setUp() {
        fauxnanceClient = new RecordingFauxnanceClient();
        clock = new MutableClock(Instant.parse("2026-10-19T14:00:00Z"));
        quoteCache = new QuoteCache(fauxnanceClient, clock, TTL);
    }

    @Test
    void firstRequestForASymbolCallsFauxnance() {
        fauxnanceClient.stub("AAPL", quote("AAPL", "232.71"));

        Map<String, Quote> result = quoteCache.getQuotes(Set.of("AAPL"));

        assertThat(result.get("AAPL").price()).isEqualByComparingTo("232.71");
        assertThat(fauxnanceClient.callCount()).isEqualTo(1);
    }

    @Test
    void aSecondRequestInsideTheTtlIsServedFromTheCacheWithoutCallingFauxnanceAgain() {
        fauxnanceClient.stub("AAPL", quote("AAPL", "232.71"));
        quoteCache.getQuotes(Set.of("AAPL"));

        clock.advance(Duration.ofSeconds(9));
        Map<String, Quote> result = quoteCache.getQuotes(Set.of("AAPL"));

        assertThat(result.get("AAPL").price()).isEqualByComparingTo("232.71");
        assertThat(fauxnanceClient.callCount()).isEqualTo(1);
    }

    @Test
    void aRequestAfterTheTtlExpiresCallsFauxnanceAgain() {
        fauxnanceClient.stub("AAPL", quote("AAPL", "232.71"));
        quoteCache.getQuotes(Set.of("AAPL"));

        clock.advance(Duration.ofSeconds(11));
        fauxnanceClient.stub("AAPL", quote("AAPL", "233.05"));
        Map<String, Quote> result = quoteCache.getQuotes(Set.of("AAPL"));

        assertThat(result.get("AAPL").price()).isEqualByComparingTo("233.05");
        assertThat(fauxnanceClient.callCount()).isEqualTo(2);
    }

    @Test
    void twoDifferentSymbolsAreCachedIndependently() {
        fauxnanceClient.stub("AAPL", quote("AAPL", "232.71"));
        fauxnanceClient.stub("SPY", quote("SPY", "500.00"));

        quoteCache.getQuotes(Set.of("AAPL"));
        clock.advance(Duration.ofSeconds(5));
        Map<String, Quote> result = quoteCache.getQuotes(Set.of("AAPL", "SPY"));

        assertThat(result).containsKeys("AAPL", "SPY");
        // AAPL was already cached and fresh; only SPY needed a Fauxnance call on the
        // second request, so the batch call for the second request asked for SPY only.
        assertThat(fauxnanceClient.lastRequestedSymbols()).containsExactly("SPY");
    }

    @Test
    void aSymbolFauxnanceCannotPriceIsAbsentFromTheResultWhenNothingIsCached() {
        // fauxnanceClient has no stub for "UNKNOWN": it returns nothing for it.
        Map<String, Quote> result = quoteCache.getQuotes(Set.of("UNKNOWN"));

        assertThat(result).doesNotContainKey("UNKNOWN");
    }

    @Test
    void whenFauxnanceFailsOnRefreshTheStaleCachedQuoteIsServedMarkedStale() {
        fauxnanceClient.stub("AAPL", quote("AAPL", "232.71"));
        quoteCache.getQuotes(Set.of("AAPL"));

        clock.advance(Duration.ofSeconds(11));
        fauxnanceClient.clearStubs();
        Map<String, Quote> result = quoteCache.getQuotes(Set.of("AAPL"));

        assertThat(result.get("AAPL").price()).isEqualByComparingTo("232.71");
        assertThat(result.get("AAPL").stale()).isTrue();
    }

    @Test
    void primingFromMarketDataMakesAPriceAvailableBeforeAnyFauxnanceCall() {
        quoteCache.primeFromMarketData(new Quote("AAPL", new BigDecimal("231.00"), "USD", clock.instant(), true));

        Map<String, Quote> result = quoteCache.getQuotes(Set.of("AAPL"));

        // The primed entry was written moments ago, well inside the freshness
        // window, so it is served from cache without a Fauxnance call.
        assertThat(result.get("AAPL").price()).isEqualByComparingTo("231.00");
        assertThat(fauxnanceClient.callCount()).isZero();
    }

    private static Quote quote(String symbol, String price) {
        return new Quote(symbol, new BigDecimal(price), "USD", Instant.parse("2026-10-19T14:00:00Z"), false);
    }

    /** A fake Fauxnance client that records every batch it was asked to fetch. */
    private static final class RecordingFauxnanceClient implements FauxnanceClient {

        private final Map<String, Quote> stubs = new LinkedHashMap<>();
        private int callCount = 0;
        private List<String> lastRequestedSymbols = List.of();

        void stub(String symbol, Quote quote) {
            stubs.put(symbol, quote);
        }

        void clearStubs() {
            stubs.clear();
        }

        int callCount() {
            return callCount;
        }

        List<String> lastRequestedSymbols() {
            return lastRequestedSymbols;
        }

        @Override
        public Map<String, Quote> getQuotes(List<String> symbols) {
            callCount++;
            lastRequestedSymbols = List.copyOf(symbols);
            Map<String, Quote> result = new LinkedHashMap<>();
            for (String symbol : symbols) {
                Quote stubbed = stubs.get(symbol);
                if (stubbed != null) {
                    result.put(symbol, stubbed);
                }
            }
            return result;
        }

        @Override
        public Integer getQuotaRemaining() {
            return 2000;
        }
    }

    /** A {@link Clock} whose instant can be advanced deterministically, for cache-expiry tests. */
    private static final class MutableClock extends Clock {

        private Instant instant;

        MutableClock(Instant instant) {
            this.instant = instant;
        }

        void advance(Duration duration) {
            instant = instant.plus(duration);
        }

        @Override
        public ZoneId getZone() {
            return ZoneId.of("UTC");
        }

        @Override
        public Clock withZone(ZoneId zone) {
            throw new UnsupportedOperationException();
        }

        @Override
        public Instant instant() {
            return instant;
        }
    }
}

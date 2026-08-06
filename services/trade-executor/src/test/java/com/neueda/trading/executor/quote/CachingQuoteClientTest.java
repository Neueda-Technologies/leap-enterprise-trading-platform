package com.neueda.trading.executor.quote;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;

/**
 * The cache exists to protect a 2000 request per day quota, so the tests count requests rather than
 * inspect prices.
 */
class CachingQuoteClientTest {

    private static final Instant START = Instant.parse("2026-09-28T09:14:24Z");

    private final MutableClock clock = new MutableClock(START);
    private final CountingQuoteClient delegate = new CountingQuoteClient();

    private final CachingQuoteClient client =
            new CachingQuoteClient(delegate, Duration.ofSeconds(5), clock);

    @Test
    void aSecondLookupInsideTheWindowCostsNoRequest() {
        client.quoteFor("AAPL");
        clock.advance(Duration.ofSeconds(4));
        Optional<Quote> second = client.quoteFor("AAPL");

        assertThat(second).isPresent();
        assertThat(delegate.calls()).isEqualTo(1);
    }

    @Test
    void aLookupAfterTheWindowFetchesAgain() {
        client.quoteFor("AAPL");
        clock.advance(Duration.ofSeconds(5));
        client.quoteFor("AAPL");

        assertThat(delegate.calls()).isEqualTo(2);
    }

    @Test
    void symbolsAreCachedIndependently() {
        client.quoteFor("AAPL");
        client.quoteFor("MSFT");
        client.quoteFor("AAPL");

        assertThat(delegate.calls()).isEqualTo(2);
    }

    @Test
    void aFailedLookupIsNotCached() {
        delegate.failNext();

        assertThat(client.quoteFor("AAPL")).isEmpty();
        assertThat(client.quoteFor("AAPL")).isPresent();
        assertThat(delegate.calls()).isEqualTo(2);
    }

    @Test
    void clearingTheCacheForcesTheNextLookupToFetch() {
        client.quoteFor("AAPL");
        client.clear();
        client.quoteFor("AAPL");

        assertThat(delegate.calls()).isEqualTo(2);
    }

    /** A hand-written stub, because what is being asserted is how often it was called. */
    private static final class CountingQuoteClient implements QuoteClient {

        private final AtomicInteger calls = new AtomicInteger();
        private boolean failNext;

        @Override
        public Optional<Quote> quoteFor(String symbol) {
            calls.incrementAndGet();
            if (failNext) {
                failNext = false;
                return Optional.empty();
            }
            return Optional.of(new Quote(symbol, new BigDecimal("232.71"), "USD", START, "open", false));
        }

        void failNext() {
            this.failNext = true;
        }

        int calls() {
            return calls.get();
        }
    }

    /** {@link Clock#tick} cannot be moved, so the tests use a clock that can. */
    private static final class MutableClock extends Clock {

        private Instant now;

        private MutableClock(Instant now) {
            this.now = now;
        }

        void advance(Duration amount) {
            now = now.plus(amount);
        }

        @Override
        public ZoneOffset getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(java.time.ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }
}

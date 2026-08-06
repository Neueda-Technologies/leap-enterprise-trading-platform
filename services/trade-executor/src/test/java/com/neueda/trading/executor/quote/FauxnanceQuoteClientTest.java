package com.neueda.trading.executor.quote;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.neueda.trading.executor.config.FauxnanceProperties;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.ExpectedCount;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

/**
 * The HTTP layer is faked with {@link MockRestServiceServer}. What is being tested is which status
 * codes cost a retry and which do not, because that decision is what protects the daily quota.
 */
class FauxnanceQuoteClientTest {

    private static final String QUOTE_BODY = """
            {
              "data": {
                "symbol": "AAPL",
                "price": 232.7149,
                "currency": "USD",
                "change": 0.21,
                "changePercent": 0.09,
                "previousClose": 232.50,
                "asOf": "2026-09-28T09:14:58Z",
                "marketState": "open"
              },
              "meta": {
                "asOf": "2026-09-28T09:15:00Z",
                "disclaimer": "Educational data. Not for investment use.",
                "symbol": "AAPL",
                "source": "cache",
                "stale": false
              }
            }
            """;

    private final FauxnanceProperties properties = new FauxnanceProperties();

    private MockRestServiceServer server;
    private FauxnanceQuoteClient client;

    @BeforeEach
    void setUp() {
        properties.setBaseUrl("https://fauxnance.test/v1");
        properties.setApiKey("test-key");
        properties.setMaxAttempts(2);
        properties.setRetryBackoff(Duration.ZERO);

        RestClient.Builder builder = RestClient.builder().baseUrl(properties.getBaseUrl())
                .defaultHeader("X-Api-Key", properties.getApiKey());
        server = MockRestServiceServer.bindTo(builder).build();
        client = new FauxnanceQuoteClient(builder.build(), properties);
    }

    @Test
    void aQuoteIsParsedWithTheKeyInTheHeader() {
        server.expect(requestTo("https://fauxnance.test/v1/quotes/AAPL"))
                .andExpect(header("X-Api-Key", "test-key"))
                .andRespond(withSuccess(QUOTE_BODY, MediaType.APPLICATION_JSON));

        Optional<Quote> quote = client.quoteFor("AAPL");

        assertThat(quote).isPresent();
        assertThat(quote.get().price()).isEqualByComparingTo("232.7149");
        assertThat(quote.get().currency()).isEqualTo("USD");
        assertThat(quote.get().marketState()).isEqualTo("open");
        assertThat(quote.get().asOf()).isEqualTo(Instant.parse("2026-09-28T09:14:58Z"));
        assertThat(quote.get().stale()).isFalse();
        server.verify();
    }

    @Test
    void anUnknownSymbolIsNotRetried() {
        server.expect(ExpectedCount.once(), requestTo("https://fauxnance.test/v1/quotes/NOPE"))
                .andRespond(withStatus(HttpStatus.NOT_FOUND));

        assertThat(client.quoteFor("NOPE")).isEmpty();
        server.verify();
    }

    @Test
    void anExhaustedQuotaIsNotRetried() {
        server.expect(ExpectedCount.once(), requestTo("https://fauxnance.test/v1/quotes/AAPL"))
                .andRespond(withStatus(HttpStatus.TOO_MANY_REQUESTS));

        assertThat(client.quoteFor("AAPL")).isEmpty();
        server.verify();
    }

    @Test
    void aBackfillInProgressIsRetried() {
        server.expect(ExpectedCount.once(), requestTo("https://fauxnance.test/v1/quotes/AAPL"))
                .andRespond(withStatus(HttpStatus.ACCEPTED)
                        .body("{\"error\":{\"code\":\"BACKFILL_IN_PROGRESS\"}}")
                        .contentType(MediaType.APPLICATION_JSON));
        server.expect(ExpectedCount.once(), requestTo("https://fauxnance.test/v1/quotes/AAPL"))
                .andRespond(withSuccess(QUOTE_BODY, MediaType.APPLICATION_JSON));

        assertThat(client.quoteFor("AAPL")).isPresent();
        server.verify();
    }

    @Test
    void anUpstreamFailureIsRetriedUntilTheBudgetIsSpent() {
        server.expect(ExpectedCount.times(2), requestTo("https://fauxnance.test/v1/quotes/AAPL"))
                .andRespond(withStatus(HttpStatus.SERVICE_UNAVAILABLE));

        assertThat(client.quoteFor("AAPL")).isEmpty();
        server.verify();
    }
}

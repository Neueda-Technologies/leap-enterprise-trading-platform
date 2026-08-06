package com.neueda.trading.executor.quote;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.neueda.trading.executor.config.FauxnanceProperties;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.util.UriComponentsBuilder;

/**
 * Calls {@code GET /quotes/{symbol}} on the Fauxnance API.
 *
 * <p>Response classes are handled differently, and the difference is the whole point of the class.
 * A 404 means the symbol does not exist in the Fauxnance scheme and will not exist on the next
 * attempt, so it returns empty immediately. A 429 means the daily quota is spent, and it does not
 * refill inside a retry window, so it also returns empty, with a log line that names the cause. A
 * 202 means Fauxnance is backfilling the symbol and will have a price shortly, so it is retried.
 * Anything else, a 5xx or a connection failure, is transient and is retried with backoff until the
 * attempt budget runs out.
 */
public class FauxnanceQuoteClient implements QuoteClient {

    private static final Logger log = LoggerFactory.getLogger(FauxnanceQuoteClient.class);

    private final RestClient restClient;
    private final FauxnanceProperties properties;

    public FauxnanceQuoteClient(RestClient restClient, FauxnanceProperties properties) {
        this.restClient = restClient;
        this.properties = properties;
    }

    @Override
    public Optional<Quote> quoteFor(String symbol) {
        int attempts = Math.max(1, properties.getMaxAttempts());
        for (int attempt = 1; attempt <= attempts; attempt++) {
            try {
                return Optional.ofNullable(fetch(symbol));
            } catch (HttpClientErrorException.NotFound e) {
                log.warn("Fauxnance has no quote for symbol {}", symbol);
                return Optional.empty();
            } catch (HttpClientErrorException e) {
                if (e.getStatusCode() == HttpStatus.TOO_MANY_REQUESTS) {
                    log.error("Fauxnance quota exhausted for this key. Check GET /usage.");
                    return Optional.empty();
                }
                log.warn("Fauxnance rejected the quote request for {}: {}", symbol, e.getStatusCode());
                return Optional.empty();
            } catch (RestClientException e) {
                log.warn("Quote lookup for {} failed on attempt {} of {}: {}",
                        symbol, attempt, attempts, e.getMessage());
                if (attempt == attempts) {
                    return Optional.empty();
                }
                sleepBackoff(attempt);
            }
        }
        return Optional.empty();
    }

    private Quote fetch(String symbol) {
        String path = UriComponentsBuilder.fromPath("/quotes/{symbol}")
                .buildAndExpand(symbol)
                .toUriString();
        ResponseEntity<QuoteResponse> response = restClient.get()
                .uri(path)
                .retrieve()
                .toEntity(QuoteResponse.class);

        // 202 means Fauxnance is backfilling the symbol and has no real price yet. It is a success
        // status, so nothing has thrown, but the answer is "ask again shortly".
        if (response.getStatusCode() == HttpStatus.ACCEPTED) {
            throw new BackfillInProgressException(symbol);
        }
        QuoteResponse body = response.getBody();
        if (body == null || body.data() == null || body.data().price() == null) {
            log.warn("Fauxnance returned a quote for {} with no price", symbol);
            return null;
        }
        QuoteData data = body.data();
        boolean stale = body.meta() != null && Boolean.TRUE.equals(body.meta().stale());
        return new Quote(
                symbol,
                data.price(),
                data.currency(),
                data.asOf(),
                data.marketState() == null ? "unknown" : data.marketState(),
                stale);
    }

    private void sleepBackoff(int attempt) {
        long millis = properties.getRetryBackoff().toMillis() * attempt;
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while backing off a quote retry", e);
        }
    }

    /** Transient by definition: Fauxnance is fetching the data and will have it shortly. */
    static class BackfillInProgressException extends RestClientException {

        BackfillInProgressException(String symbol) {
            super("Fauxnance is still backfilling " + symbol);
        }
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record QuoteResponse(QuoteData data, QuoteMeta meta) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record QuoteData(
            BigDecimal price,
            String currency,
            BigDecimal change,
            BigDecimal changePercent,
            BigDecimal previousClose,
            Instant asOf,
            String marketState) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record QuoteMeta(Boolean stale) {
    }
}

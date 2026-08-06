package com.neueda.trading.executor.config;

import com.neueda.trading.executor.execution.ExecutionLatency;
import com.neueda.trading.executor.quote.CachingQuoteClient;
import com.neueda.trading.executor.quote.FauxnanceQuoteClient;
import com.neueda.trading.executor.quote.QuoteClient;
import java.time.Clock;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.client.RestClient;

/** Wiring for the quote client, the latency simulator and the transaction template. */
@Configuration
public class ExecutionConfig {

    private static final Logger log = LoggerFactory.getLogger(ExecutionConfig.class);

    /**
     * The cache wraps the HTTP client rather than the other way round, so a cache hit costs no
     * request against the 2000 per day quota and a cache miss still gets the retry behaviour.
     */
    @Bean
    QuoteClient quoteClient(RestClient.Builder builder, FauxnanceProperties properties, Clock clock) {
        if (properties.getApiKey().isBlank()) {
            log.warn("FAUXNANCE_API_KEY is not set. Every quote lookup will fail and every order "
                    + "will be rejected with PRICING_UNAVAILABLE.");
        }
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(properties.getConnectTimeout());
        requestFactory.setReadTimeout(properties.getReadTimeout());

        RestClient restClient = builder
                .baseUrl(properties.getBaseUrl())
                .defaultHeader("X-Api-Key", properties.getApiKey())
                .requestFactory(requestFactory)
                .build();

        return new CachingQuoteClient(
                new FauxnanceQuoteClient(restClient, properties),
                properties.getQuoteMaxAge(),
                clock);
    }

    @Bean
    ExecutionLatency executionLatency(ExecutorProperties properties) {
        return new ExecutionLatency(properties.getLatency().getMin(), properties.getLatency().getMax());
    }

    /**
     * A template rather than {@code @Transactional}, because the optimistic-lock retry loop has to
     * sit outside the transaction. Retrying inside a transaction that has already rolled back does
     * nothing.
     */
    @Bean
    TransactionTemplate transactionTemplate(PlatformTransactionManager transactionManager) {
        return new TransactionTemplate(transactionManager);
    }
}

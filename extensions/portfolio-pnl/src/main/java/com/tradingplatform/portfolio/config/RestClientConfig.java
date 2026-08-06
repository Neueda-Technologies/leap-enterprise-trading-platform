package com.tradingplatform.portfolio.config;

import com.tradingplatform.portfolio.fauxnance.FauxnanceProperties;
import java.time.Duration;
import org.springframework.boot.web.client.ClientHttpRequestFactories;
import org.springframework.boot.web.client.ClientHttpRequestFactorySettings;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.ClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

/**
 * A dedicated HTTP client for Fauxnance, carrying the {@code X-Api-Key} header on
 * every call. The key comes from an environment variable and is never logged, never
 * returned to a caller, and never reaches the Angular UI: this service is the only
 * thing between a browser and a priced portfolio.
 */
@Configuration
public class RestClientConfig {

    @Bean
    public RestClient fauxnanceRestClient(FauxnanceProperties properties) {
        ClientHttpRequestFactorySettings settings = ClientHttpRequestFactorySettings.DEFAULTS
                .withConnectTimeout(Duration.ofMillis(properties.connectTimeoutMs()))
                .withReadTimeout(Duration.ofMillis(properties.readTimeoutMs()));
        ClientHttpRequestFactory requestFactory = ClientHttpRequestFactories.get(settings);

        return RestClient.builder()
                .baseUrl(properties.baseUrl())
                .requestFactory(requestFactory)
                .defaultHeader("X-Api-Key", properties.apiKey() == null ? "" : properties.apiKey())
                .build();
    }
}

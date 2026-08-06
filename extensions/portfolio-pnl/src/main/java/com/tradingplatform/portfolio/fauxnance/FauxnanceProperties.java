package com.tradingplatform.portfolio.fauxnance;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "fauxnance")
public record FauxnanceProperties(
        String baseUrl,
        String apiKey,
        int quoteCacheTtlSeconds,
        int quoteBatchSize,
        int connectTimeoutMs,
        int readTimeoutMs) {
}

package com.neueda.trading.executor.config;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Fauxnance API client settings. The key is read from the {@code FAUXNANCE_API_KEY} environment
 * variable and must never be written into a committed file.
 */
@ConfigurationProperties(prefix = "fauxnance")
public class FauxnanceProperties {

    private String baseUrl = "https://y4t9nq2bqf.execute-api.eu-west-2.amazonaws.com/v1";
    private String apiKey = "";

    /**
     * How old a cached quote may be before the executor fetches a new one. Five seconds keeps a
     * burst of orders on the same symbol down to one request against the 2000 per day quota while
     * still pricing each fill against a price nobody would call historical.
     */
    private Duration quoteMaxAge = Duration.ofSeconds(5);

    private Duration connectTimeout = Duration.ofSeconds(2);
    private Duration readTimeout = Duration.ofSeconds(3);

    /**
     * Attempts per quote lookup, counting the first. Fauxnance 5xx responses and connection
     * failures are transient and worth retrying inside the message handler. A 404 is not.
     */
    private int maxAttempts = 3;

    private Duration retryBackoff = Duration.ofMillis(200);

    public String getBaseUrl() {
        return baseUrl;
    }

    public void setBaseUrl(String baseUrl) {
        this.baseUrl = baseUrl;
    }

    public String getApiKey() {
        return apiKey;
    }

    public void setApiKey(String apiKey) {
        this.apiKey = apiKey;
    }

    public Duration getQuoteMaxAge() {
        return quoteMaxAge;
    }

    public void setQuoteMaxAge(Duration quoteMaxAge) {
        this.quoteMaxAge = quoteMaxAge;
    }

    public Duration getConnectTimeout() {
        return connectTimeout;
    }

    public void setConnectTimeout(Duration connectTimeout) {
        this.connectTimeout = connectTimeout;
    }

    public Duration getReadTimeout() {
        return readTimeout;
    }

    public void setReadTimeout(Duration readTimeout) {
        this.readTimeout = readTimeout;
    }

    public int getMaxAttempts() {
        return maxAttempts;
    }

    public void setMaxAttempts(int maxAttempts) {
        this.maxAttempts = maxAttempts;
    }

    public Duration getRetryBackoff() {
        return retryBackoff;
    }

    public void setRetryBackoff(Duration retryBackoff) {
        this.retryBackoff = retryBackoff;
    }
}

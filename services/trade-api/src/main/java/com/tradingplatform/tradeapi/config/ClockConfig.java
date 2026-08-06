package com.tradingplatform.tradeapi.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;

/**
 * The clock, as a bean.
 *
 * <p>Nothing in this service calls {@code Instant.now()}. Time is injected, for two reasons that both
 * bite eventually. A service that reads the system clock directly cannot be tested at a fixed
 * instant, so its tests either avoid asserting on time or become flaky. And the instant recorded on
 * the order row must be the same instant that reaches the Kafka payload; two separate calls to
 * {@code now()} are two different values, and a consumer reconciling them will find a discrepancy it
 * cannot explain.
 *
 * <p>UTC, not the system default zone. A platform spanning Dublin, Boston and Bangalore has no single
 * local time, and a container's idea of local time is whatever the base image happened to ship.
 */
@Configuration
public class ClockConfig {

    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }
}

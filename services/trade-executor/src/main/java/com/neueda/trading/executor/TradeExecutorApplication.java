package com.neueda.trading.executor;

import com.neueda.trading.executor.config.ExecutorProperties;
import com.neueda.trading.executor.config.FauxnanceProperties;
import java.time.Clock;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;

/**
 * The Trade Executor is the execution venue. No broker simulator exists: this service consumes
 * accepted orders, prices them against the Fauxnance API, and settles them in Postgres.
 */
@SpringBootApplication
@EnableConfigurationProperties({ExecutorProperties.class, FauxnanceProperties.class})
public class TradeExecutorApplication {

    public static void main(String[] args) {
        SpringApplication.run(TradeExecutorApplication.class, args);
    }

    /**
     * Injected rather than called statically so that tests can pin the execution timestamp.
     */
    @Bean
    Clock clock() {
        return Clock.systemUTC();
    }
}

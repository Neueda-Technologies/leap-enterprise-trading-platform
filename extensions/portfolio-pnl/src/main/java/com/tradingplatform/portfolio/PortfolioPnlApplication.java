package com.tradingplatform.portfolio;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

/**
 * Portfolio and P&amp;L service. Consolidated holdings, cost basis, and
 * realised and unrealised profit and loss, per docs/contracts/portfolio-api.yaml.
 *
 * <p>This service reads {@code accounts}, {@code instruments} and {@code positions}
 * from the shared trading schema, read-only. It never writes to them. Its own write
 * path is the realised profit-and-loss ledger, built from {@code trade-events}.
 */
@SpringBootApplication
@ConfigurationPropertiesScan
public class PortfolioPnlApplication {

    public static void main(String[] args) {
        SpringApplication.run(PortfolioPnlApplication.class, args);
    }
}

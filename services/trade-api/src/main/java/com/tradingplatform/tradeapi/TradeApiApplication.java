package com.tradingplatform.tradeapi;

import com.tradingplatform.tradeapi.config.TradingProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

/**
 * The Trade REST API.
 *
 * <p>The write path of the platform. It validates an order against the business rules, records it,
 * and either fills it in process or publishes it for the Trade Executor. It also serves the account
 * queries the dashboard reads: details, balance, holdings and the order blotter.
 *
 * <p>What it deliberately does not do: it does not price an order, it does not call the Fauxnance
 * API, and from Sprint 7 it does not move money. Recording intent and executing it are separate
 * responsibilities held by separate processes, because execution takes time and can fail.
 *
 * <p>There is deliberately no {@code @MapperScan} here. The MyBatis auto-configuration finds the
 * {@code @Mapper} interfaces on its own, and it only does so when the MyBatis auto-configuration is
 * active. An explicit {@code @MapperScan} registers mapper beans in every context that imports this
 * class, including a {@code @WebMvcTest} slice that has no {@code SqlSessionFactory}, and the slice
 * then fails to start for a reason that has nothing to do with the web layer under test.
 */
@SpringBootApplication
@EnableConfigurationProperties(TradingProperties.class)
public class TradeApiApplication {

    public static void main(String[] args) {
        SpringApplication.run(TradeApiApplication.class, args);
    }
}

package com.tradingplatform.tradeapi.config;

import com.tradingplatform.domain.service.IdempotencyKeyRegistry;
import com.tradingplatform.domain.service.OrderPlacementService;
import com.tradingplatform.domain.service.SettlementService;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Exposes the domain services as beans.
 *
 * <p>The domain module carries no Spring annotations, so its classes cannot be component scanned.
 * That is the design working, not an inconvenience to route around. A domain that depends on a
 * container cannot be used by anything that is not that container, and the Trade Executor in Sprint 7
 * may not be a Spring application at all.
 *
 * <p>Both services are stateless and safe to share, so one instance each is enough.
 */
@Configuration
public class DomainConfig {

    /**
     * Business rule 8 is delegated to the unique constraint on {@code orders.idempotency_key}, so the
     * registry knows nothing. Replacing this with a lookup would put a select in front of the insert
     * and reopen the race the constraint closes.
     */
    @Bean
    public OrderPlacementService orderPlacementService() {
        return new OrderPlacementService(IdempotencyKeyRegistry.none());
    }

    @Bean
    public SettlementService settlementService() {
        return new SettlementService();
    }
}

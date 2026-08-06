package com.tradingplatform.tradeapi;

import com.tradingplatform.tradeapi.config.TradingProperties;
import com.tradingplatform.tradeapi.messaging.KafkaEventPublisher;
import com.tradingplatform.tradeapi.repository.AccountMapper;
import com.tradingplatform.tradeapi.web.AccountController;
import com.tradingplatform.tradeapi.web.GlobalExceptionHandler;
import com.tradingplatform.tradeapi.web.OrderController;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.test.context.TestPropertySource;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * The whole application context starts.
 *
 * <p>Cheap and worth having. It catches a property that does not bind, a bean that cannot be
 * constructed and a mapper XML that does not parse, all of which otherwise surface on a container
 * start in front of somebody else.
 *
 * <p>H2 stands in for Postgres because no query runs here, and Kafka publishing is switched off, so
 * the test needs neither container.
 */
@SpringBootTest
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:h2:mem:contexttest;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "trading.kafka.enabled=false",
        "trading.execution-mode=sync"
})
@DisplayName("Application context")
class ApplicationContextTest {

    @Autowired private ApplicationContext context;
    @Autowired private TradingProperties properties;

    @Test
    @DisplayName("every layer is wired: controllers, the handler, the mappers and the domain")
    void testContextLoads() {
        assertNotNull(context.getBean(OrderController.class));
        assertNotNull(context.getBean(AccountController.class));
        assertNotNull(context.getBean(GlobalExceptionHandler.class));
        assertNotNull(context.getBean(AccountMapper.class));
        assertNotNull(context.getBean(com.tradingplatform.domain.service.OrderPlacementService.class));
        assertNotNull(context.getBean(com.tradingplatform.domain.service.SettlementService.class));
    }

    @Test
    @DisplayName("the execution mode binds from the property, which is how Sprint 6 is reachable")
    void testExecutionModeBinds() {
        assertEquals(com.tradingplatform.tradeapi.config.ExecutionMode.SYNC, properties.executionMode());
    }

    @Test
    @DisplayName("switching Kafka off removes the publisher rather than leaving a broken one")
    void testKafkaPublisherIsAbsentWhenDisabled() {
        assertFalse(properties.kafka().enabled());
        assertTrue(context.getBeanNamesForType(KafkaEventPublisher.class).length == 0);
    }

    @Test
    @DisplayName("the JWT filter is mapped onto /api/* and nothing else")
    void testProtectedPatternIsMapped() {
        var registration = context.getBean("jwtAuthenticationFilter",
                org.springframework.boot.web.servlet.FilterRegistrationBean.class);

        assertEquals(java.util.Set.of("/api/*"), registration.getUrlPatterns());
    }
}

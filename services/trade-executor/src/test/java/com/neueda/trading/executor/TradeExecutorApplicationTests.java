package com.neueda.trading.executor;

import static org.assertj.core.api.Assertions.assertThat;

import com.neueda.trading.executor.config.ExecutorProperties;
import com.neueda.trading.executor.config.FauxnanceProperties;
import com.neueda.trading.executor.execution.OrderExecutionService;
import com.neueda.trading.executor.messaging.OrderPlacedListener;
import com.neueda.trading.executor.messaging.TradeEventPublisher;
import com.neueda.trading.executor.quote.QuoteClient;
import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.kafka.listener.DefaultErrorHandler;

/**
 * Proves the context wires. Every other test in this module runs without Spring, which is the right
 * default, but it leaves nothing checking that the beans actually connect to each other.
 *
 * <p>The listener container is stopped before it starts and the datasource points nowhere: neither
 * connects during context refresh, so this needs no broker and no database.
 */
@SpringBootTest(properties = {
        "spring.kafka.listener.auto-startup=false",
        "spring.kafka.bootstrap-servers=localhost:19092",
        "spring.datasource.url=jdbc:postgresql://localhost:5432/none",
        "spring.datasource.username=none",
        "spring.datasource.password=none",
        "fauxnance.api-key=test-key",
        "server.port=0"
})
class TradeExecutorApplicationTests {

    @Autowired
    private OrderExecutionService executionService;

    @Autowired
    private OrderPlacedListener listener;

    @Autowired
    private TradeEventPublisher publisher;

    @Autowired
    private QuoteClient quoteClient;

    @Autowired
    private DefaultErrorHandler errorHandler;

    @Autowired
    private ExecutorProperties executorProperties;

    @Autowired
    private FauxnanceProperties fauxnanceProperties;

    @Test
    void everyCollaboratorIsWired() {
        assertThat(executionService).isNotNull();
        assertThat(listener).isNotNull();
        assertThat(publisher).isNotNull();
        assertThat(quoteClient).isNotNull();
        assertThat(errorHandler).isNotNull();
    }

    @Test
    void theDefaultsMatchTheDocumentedOnes() {
        assertThat(executorProperties.getTopics().getOrders()).isEqualTo("orders");
        assertThat(executorProperties.getTopics().getTradeEvents()).isEqualTo("trade-events");
        assertThat(executorProperties.getTopics().getDeadLetterSuffix()).isEqualTo(".DLT");
        assertThat(executorProperties.getMaxDeliveryAttempts()).isEqualTo(4);
        assertThat(executorProperties.getLatency().getMin()).isEqualTo(Duration.ofMillis(250));
        assertThat(executorProperties.getLatency().getMax()).isEqualTo(Duration.ofMillis(750));
        assertThat(fauxnanceProperties.getQuoteMaxAge()).isEqualTo(Duration.ofSeconds(5));
    }
}

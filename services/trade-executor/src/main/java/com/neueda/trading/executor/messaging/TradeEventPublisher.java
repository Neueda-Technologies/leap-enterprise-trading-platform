package com.neueda.trading.executor.messaging;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.neueda.trading.executor.config.ExecutorProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

/**
 * Publishes the outcome of an execution to {@code trade-events}.
 *
 * <p>The key is {@code accountId} as a string, which is what keeps every event for one account on
 * one partition and therefore in order. Never key by order identifier: each event would land on its
 * own partition and the per-account ordering the platform relies on would be gone.
 *
 * <p>The send is awaited rather than fired and forgotten. The caller acknowledges the offset only
 * after this returns, so a broker that is unreachable causes a redelivery instead of an order that
 * settled in Postgres and told nobody. {@code delivery.timeout.ms} bounds the wait.
 */
@Component
public class TradeEventPublisher {

    private static final Logger log = LoggerFactory.getLogger(TradeEventPublisher.class);

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper;
    private final ExecutorProperties properties;

    public TradeEventPublisher(KafkaTemplate<String, String> kafkaTemplate,
                               ObjectMapper objectMapper,
                               ExecutorProperties properties) {
        this.kafkaTemplate = kafkaTemplate;
        this.objectMapper = objectMapper;
        this.properties = properties;
    }

    public void publish(TradeEventEnvelope envelope) {
        String topic = properties.getTopics().getTradeEvents();
        String key = Long.toString(envelope.payload().accountId());
        String value = serialise(envelope);
        kafkaTemplate.send(topic, key, value).join();
        log.debug("Published {} for order {} to {}",
                envelope.eventType(), envelope.payload().orderId(), topic);
    }

    private String serialise(TradeEventEnvelope envelope) {
        try {
            return objectMapper.writeValueAsString(envelope);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(
                    "Could not serialise the trade event for order " + envelope.payload().orderId(), e);
        }
    }
}

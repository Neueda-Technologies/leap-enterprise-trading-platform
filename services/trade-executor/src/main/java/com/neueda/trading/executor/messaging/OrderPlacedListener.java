package com.neueda.trading.executor.messaging;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.neueda.trading.executor.execution.OrderExecutionService;
import java.util.Optional;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.stereotype.Component;

/**
 * The only consumer of {@code orders}. The topic is a work queue with exactly one consumer group;
 * a second group would mean two services executing the same order.
 *
 * <p>Auto-commit is off. The offset is acknowledged after the database has committed and the event
 * has been published. A crash between any two of those steps redelivers the message, and the
 * guarded status transition in {@link OrderExecutionService} makes the redelivery harmless.
 */
@Component
public class OrderPlacedListener {

    private static final Logger log = LoggerFactory.getLogger(OrderPlacedListener.class);

    private final ObjectMapper objectMapper;
    private final OrderExecutionService executionService;
    private final TradeEventPublisher publisher;

    public OrderPlacedListener(ObjectMapper objectMapper,
                               OrderExecutionService executionService,
                               TradeEventPublisher publisher) {
        this.objectMapper = objectMapper;
        this.executionService = executionService;
        this.publisher = publisher;
    }

    @KafkaListener(
            topics = "${executor.topics.orders:orders}",
            groupId = "${spring.kafka.consumer.group-id:trade-executor}")
    public void onOrderPlaced(ConsumerRecord<String, String> record, Acknowledgment acknowledgment) {
        OrderPlacedPayload payload = parse(record);
        log.debug("Consumed order {} from {}-{} offset {}",
                payload.orderId(), record.topic(), record.partition(), record.offset());

        Optional<TradeEventEnvelope> outcome = executionService.execute(payload);
        outcome.ifPresent(publisher::publish);
        acknowledgment.acknowledge();
    }

    /**
     * Turns the record value into a payload, or throws {@link NonRetryableMessageException} so that
     * the error handler dead-letters it on the first attempt. A message that will not parse now
     * will not parse in five seconds either, and retrying it blocks every account on its partition.
     */
    private OrderPlacedPayload parse(ConsumerRecord<String, String> record) {
        OrderPlacedEnvelope envelope;
        try {
            envelope = objectMapper.readValue(record.value(), OrderPlacedEnvelope.class);
        } catch (Exception e) {
            throw new NonRetryableMessageException(
                    "Could not deserialise a message from " + record.topic() + "-"
                            + record.partition() + " at offset " + record.offset(), e);
        }
        if (envelope == null || envelope.payload() == null) {
            throw new NonRetryableMessageException("Message carries no payload");
        }
        if (!OrderPlacedEnvelope.ORDER_PLACED.equals(envelope.eventType())) {
            throw new NonRetryableMessageException(
                    "Unexpected eventType " + envelope.eventType() + " on the orders topic");
        }
        return envelope.payload();
    }
}

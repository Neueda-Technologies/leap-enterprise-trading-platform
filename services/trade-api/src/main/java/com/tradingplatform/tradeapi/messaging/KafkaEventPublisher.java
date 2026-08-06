package com.tradingplatform.tradeapi.messaging;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.tradingplatform.tradeapi.config.TradingProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.time.Clock;
import java.time.Instant;

/**
 * Publishes accepted orders and customer cancellations to Kafka.
 *
 * <p>Both listeners run {@code AFTER_COMMIT}. That is the whole design and it is worth stating why.
 * Publishing inside the transaction risks an event for an order that was then rolled back, and there
 * is no way to recall it: a consumer has already executed a trade that the system of record says
 * never happened. Publishing after the commit risks a committed order that was never published,
 * which is recoverable by replaying from the order table. Choose the recoverable failure.
 *
 * <p>A send that fails is logged and does not fail the request. The order is already committed, and
 * turning a broker problem into a 500 would tell the customer their order was refused when it was
 * accepted. Recovery is a sweep over orders left in {@code NEW} past a threshold, which a team should
 * build once they have seen the failure.
 *
 * <p>The bean is absent when {@code trading.kafka.enabled} is false. The application event is then
 * published to nobody, which is exactly the Sprint 6 state: no broker, no executor, nothing
 * listening.
 */
@Component
@ConditionalOnProperty(name = "trading.kafka.enabled", havingValue = "true", matchIfMissing = true)
public class KafkaEventPublisher {

    private static final Logger log = LoggerFactory.getLogger(KafkaEventPublisher.class);

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper;
    private final TradingProperties properties;
    private final Clock clock;

    public KafkaEventPublisher(KafkaTemplate<String, String> kafkaTemplate,
                               ObjectMapper objectMapper,
                               TradingProperties properties,
                               Clock clock) {
        this.kafkaTemplate = kafkaTemplate;
        this.objectMapper = objectMapper;
        this.properties = properties;
        this.clock = clock;
    }

    /** An order was accepted and recorded. Goes to {@code orders} for the Trade Executor. */
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onOrderPlaced(OrderPlacedPayload payload) {
        send(properties.kafka().ordersTopic(),
                String.valueOf(payload.accountId()),
                EventEnvelope.from(OrderPlacedPayload.EVENT_TYPE, clock.instant(), payload));
    }

    /** An order reached a terminal status here. In this service that means a cancellation. */
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onTradeEvent(TradeEventPayload payload) {
        send(properties.kafka().tradeEventsTopic(),
                String.valueOf(payload.accountId()),
                EventEnvelope.from(payload.eventType(), clock.instant(), payload));
    }

    /**
     * Keys every message by {@code accountId}. The key decides the partition and the partition
     * decides the ordering guarantee, so two orders on one account are executed in the order they
     * were accepted. Keying by order identifier would put every message on its own partition and lose
     * that, which is how a sell gets processed before the buy that made it possible.
     */
    private void send(String topic, String key, EventEnvelope<?> envelope) {
        String value;
        try {
            value = objectMapper.writeValueAsString(envelope);
        } catch (JsonProcessingException e) {
            log.error("Could not serialise event topic={} eventType={} eventId={}",
                    topic, envelope.eventType(), envelope.eventId(), e);
            return;
        }

        Instant sentAt = clock.instant();
        kafkaTemplate.send(topic, key, value).whenComplete((result, failure) -> {
            if (failure != null) {
                log.error("Failed to publish topic={} key={} eventType={} eventId={}",
                        topic, key, envelope.eventType(), envelope.eventId(), failure);
            } else {
                log.info("Published topic={} partition={} offset={} key={} eventType={} eventId={} latencyMs={}",
                        topic,
                        result.getRecordMetadata().partition(),
                        result.getRecordMetadata().offset(),
                        key,
                        envelope.eventType(),
                        envelope.eventId(),
                        clock.instant().toEpochMilli() - sentAt.toEpochMilli());
            }
        });
    }
}

package com.tradingplatform.portfolio.kafka;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.tradingplatform.portfolio.ledger.PnlLedgerService;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.stereotype.Component;

/**
 * Consumes {@code trade-events}, group {@code portfolio-service}, per the producer and
 * consumer matrix in docs/contracts/kafka-topics.md. Feeds the realised profit-and-loss
 * ledger. Positions themselves are read straight from Postgres, so this consumer does
 * not maintain a position projection; it only books realised profit and loss.
 *
 * <p>Offsets are committed manually, after processing, matching the platform's
 * at-least-once contract: a crash before the commit reprocesses the message, which is
 * safe because booking is idempotent on {@code eventId}.
 *
 * <p>A message that fails to parse is logged and acknowledged rather than retried
 * forever: retrying a malformed message blocks every account keyed to its partition. A
 * production build routes it to {@code trade-events.DLT} instead of discarding it; that
 * producer is not wired up here, and the gap is called out in the README.
 */
@Component
public class TradeEventsConsumer {

    private static final Logger log = LoggerFactory.getLogger(TradeEventsConsumer.class);

    private static final String EVENT_TYPE_ORDER_FILLED = "ORDER_FILLED";
    private static final String SIDE_SELL = "SELL";

    private final ObjectMapper objectMapper;
    private final PnlLedgerService pnlLedgerService;

    public TradeEventsConsumer(ObjectMapper objectMapper, PnlLedgerService pnlLedgerService) {
        this.objectMapper = objectMapper;
        this.pnlLedgerService = pnlLedgerService;
    }

    @KafkaListener(topics = "trade-events", groupId = "portfolio-service")
    public void onMessage(ConsumerRecord<String, String> record, Acknowledgment acknowledgment) {
        try {
            EventEnvelope envelope = objectMapper.readValue(record.value(), EventEnvelope.class);

            if (EVENT_TYPE_ORDER_FILLED.equals(envelope.eventType())) {
                TradeEventPayload payload = objectMapper.treeToValue(envelope.payload(), TradeEventPayload.class);
                if (SIDE_SELL.equals(payload.side())) {
                    pnlLedgerService.recordSaleIfNew(envelope.eventId(), payload);
                }
                // A BUY fill changes average cost, but positions are read live from
                // Postgres, so there is nothing for this service to project or store.
            }
            // REJECTED and CANCELLED events, and FILLED BUY events, have no realised
            // profit-and-loss effect. They are consumed and acknowledged, not ignored
            // at the broker, so consumer lag reflects the true position in the log.
        } catch (Exception e) {
            log.error(
                    "Failed to process trade-events message at offset {} on partition {}: {}",
                    record.offset(),
                    record.partition(),
                    e.getMessage(),
                    e);
            // See class Javadoc: a real deployment dead-letters this instead.
        } finally {
            acknowledgment.acknowledge();
        }
    }
}

package com.tradingplatform.portfolio.kafka;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.tradingplatform.portfolio.fauxnance.Quote;
import com.tradingplatform.portfolio.fauxnance.QuoteCache;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.stereotype.Component;

/**
 * Consumes {@code market-data}, group {@code portfolio-service}. Pricing itself comes
 * from a direct batch call to Fauxnance at request time (see {@link QuoteCache}); this
 * consumer exists to keep a last-known price warm for a symbol that a live Fauxnance
 * call cannot currently reach, for example while the daily quota is exhausted. The
 * quote it primes the cache with is only ever served marked stale, never presented as
 * current.
 */
@Component
public class MarketDataConsumer {

    private static final Logger log = LoggerFactory.getLogger(MarketDataConsumer.class);

    private final ObjectMapper objectMapper;
    private final QuoteCache quoteCache;

    public MarketDataConsumer(ObjectMapper objectMapper, QuoteCache quoteCache) {
        this.objectMapper = objectMapper;
        this.quoteCache = quoteCache;
    }

    @KafkaListener(topics = "market-data", groupId = "portfolio-service")
    public void onMessage(ConsumerRecord<String, String> record, Acknowledgment acknowledgment) {
        try {
            EventEnvelope envelope = objectMapper.readValue(record.value(), EventEnvelope.class);
            MarketDataPayload payload = objectMapper.treeToValue(envelope.payload(), MarketDataPayload.class);
            if (payload.symbol() != null && payload.price() != null) {
                quoteCache.primeFromMarketData(
                        new Quote(payload.symbol(), payload.price(), payload.currency(), payload.quoteAsOf(), true));
            }
        } catch (Exception e) {
            log.error(
                    "Failed to process market-data message at offset {} on partition {}: {}",
                    record.offset(),
                    record.partition(),
                    e.getMessage(),
                    e);
        } finally {
            acknowledgment.acknowledge();
        }
    }
}

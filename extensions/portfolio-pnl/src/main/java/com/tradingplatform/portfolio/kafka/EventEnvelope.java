package com.tradingplatform.portfolio.kafka;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.JsonNode;
import java.time.Instant;
import java.util.UUID;

/**
 * The five-field envelope shared by {@code orders}, {@code trade-events} and
 * {@code market-data}, per docs/contracts/kafka-topics.md. {@code payload} is left as
 * a raw {@link JsonNode} here and converted to a topic-specific type by the consumer,
 * because the envelope is identical across topics but the payload is not.
 *
 * <p>Consumers must ignore fields they do not recognise: adding an optional field is
 * not a breaking change under the contract.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record EventEnvelope(UUID eventId, String eventType, Instant eventTime, String source, int schemaVersion, JsonNode payload) {
}

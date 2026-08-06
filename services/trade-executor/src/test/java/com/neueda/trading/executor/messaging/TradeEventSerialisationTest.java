package com.neueda.trading.executor.messaging;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.databind.json.JsonMapper;
import com.neueda.trading.executor.domain.OrderStatus;
import com.neueda.trading.executor.domain.Side;
import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * A field renamed here breaks the Portfolio service, the notification service, the analytics loader
 * and any strategy service a team writes in Sprint 10. The test pins the wire format against
 * {@code docs/contracts/kafka-topics.md}.
 */
class TradeEventSerialisationTest {

    private final ObjectMapper mapper = JsonMapper.builder()
            .enable(SerializationFeature.WRITE_BIGDECIMAL_AS_PLAIN)
            .build();

    @Test
    void aFilledEventCarriesExactlyTheContractedFields() throws Exception {
        JsonNode json = mapper.valueToTree(filled());

        assertThat(fieldNames(json)).containsExactlyInAnyOrder(
                "eventId", "eventType", "eventTime", "source", "schemaVersion", "payload");
        assertThat(fieldNames(json.get("payload"))).containsExactlyInAnyOrder(
                "orderId", "accountId", "symbol", "side", "quantity", "price", "executedPrice",
                "status", "reason", "cashDelta", "positionQuantityAfter", "averageCostAfter",
                "executedOn");
    }

    @Test
    void moneyIsSerialisedAsAPlainNumberAtTwoDecimalPlaces() throws Exception {
        String json = mapper.writeValueAsString(filled());

        assertThat(json).contains("\"executedPrice\":232.71");
        assertThat(json).contains("\"cashDelta\":-23271.00");
        assertThat(json).doesNotContain("E+");
    }

    @Test
    void aNullReasonIsWrittenRatherThanOmitted() throws Exception {
        JsonNode payload = mapper.valueToTree(filled()).get("payload");

        assertThat(payload.has("reason")).isTrue();
        assertThat(payload.get("reason").isNull()).isTrue();
    }

    @Test
    void enumsAreSerialisedAsTheContractedStrings() {
        JsonNode payload = mapper.valueToTree(filled()).get("payload");

        assertThat(payload.get("side").asText()).isEqualTo("BUY");
        assertThat(payload.get("status").asText()).isEqualTo("FILLED");
    }

    private static List<String> fieldNames(JsonNode node) {
        List<String> names = new java.util.ArrayList<>();
        node.fieldNames().forEachRemaining(names::add);
        return names;
    }

    private static TradeEventEnvelope filled() {
        TradeEventPayload payload = new TradeEventPayload(
                "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e",
                1L,
                "AAPL",
                Side.BUY,
                100,
                new BigDecimal("233.00"),
                new BigDecimal("232.71"),
                OrderStatus.FILLED,
                null,
                new BigDecimal("-23271.00"),
                300,
                new BigDecimal("229.83"),
                "2026-09-28T09:14:24Z");
        return new TradeEventEnvelope(
                "d47f9a10-3e2b-4c88-b0a1-7e6d5c4b3a29",
                TradeEventEnvelope.ORDER_FILLED,
                "2026-09-28T09:14:24Z",
                TradeEventEnvelope.SOURCE,
                TradeEventEnvelope.SCHEMA_VERSION,
                payload);
    }
}

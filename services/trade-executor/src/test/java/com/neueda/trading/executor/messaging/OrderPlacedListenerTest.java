package com.neueda.trading.executor.messaging;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.neueda.trading.executor.domain.OrderStatus;
import com.neueda.trading.executor.domain.Side;
import com.neueda.trading.executor.execution.OrderExecutionService;
import java.math.BigDecimal;
import java.util.Optional;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.kafka.support.Acknowledgment;

/**
 * The listener's job is narrow: parse, delegate, publish, acknowledge, in that order. These tests
 * check the order, because getting it wrong is how a platform loses a trade.
 */
class OrderPlacedListenerTest {

    private static final String ORDER_ID = "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e";

    private static final String VALID_MESSAGE = """
            {
              "eventId": "b19d2c5a-8f31-4d0e-9a77-1c3e5f7a9b0d",
              "eventType": "ORDER_PLACED",
              "eventTime": "2026-09-28T09:14:22Z",
              "source": "trade-api",
              "schemaVersion": 1,
              "payload": {
                "orderId": "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e",
                "accountId": 1,
                "symbol": "AAPL",
                "side": "BUY",
                "quantity": 100,
                "price": 233.00,
                "idempotencyKey": "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e",
                "createdOn": "2026-09-28T09:14:22Z"
              }
            }
            """;

    private final OrderExecutionService executionService = mock(OrderExecutionService.class);
    private final TradeEventPublisher publisher = mock(TradeEventPublisher.class);
    private final Acknowledgment acknowledgment = mock(Acknowledgment.class);

    private final OrderPlacedListener listener =
            new OrderPlacedListener(new ObjectMapper(), executionService, publisher);

    @Test
    void theContractedMessageIsParsedIntoAPayload() {
        when(executionService.execute(any())).thenReturn(Optional.empty());

        listener.onOrderPlaced(record(VALID_MESSAGE), acknowledgment);

        ArgumentCaptor<OrderPlacedPayload> captor = ArgumentCaptor.forClass(OrderPlacedPayload.class);
        verify(executionService).execute(captor.capture());
        OrderPlacedPayload payload = captor.getValue();
        assertThat(payload.orderId()).hasToString(ORDER_ID);
        assertThat(payload.accountId()).isEqualTo(1L);
        assertThat(payload.side()).isEqualTo(Side.BUY);
        assertThat(payload.price()).isEqualByComparingTo("233.00");
    }

    @Test
    void anUnknownFieldIsIgnoredRatherThanFailing() {
        String withExtraField = VALID_MESSAGE.replace(
                "\"schemaVersion\": 1,", "\"schemaVersion\": 1, \"traceId\": \"abc\",");
        when(executionService.execute(any())).thenReturn(Optional.empty());

        listener.onOrderPlaced(record(withExtraField), acknowledgment);

        verify(executionService).execute(any());
    }

    @Test
    void anOutcomeIsPublishedBeforeTheOffsetIsAcknowledged() {
        TradeEventEnvelope envelope = envelope();
        when(executionService.execute(any())).thenReturn(Optional.of(envelope));

        listener.onOrderPlaced(record(VALID_MESSAGE), acknowledgment);

        var inOrder = org.mockito.Mockito.inOrder(publisher, acknowledgment);
        inOrder.verify(publisher).publish(envelope);
        inOrder.verify(acknowledgment).acknowledge();
    }

    @Test
    void aDuplicateDeliveryIsAcknowledgedWithoutPublishingAnything() {
        when(executionService.execute(any())).thenReturn(Optional.empty());

        listener.onOrderPlaced(record(VALID_MESSAGE), acknowledgment);

        verify(publisher, never()).publish(any());
        verify(acknowledgment).acknowledge();
    }

    @Test
    void malformedJsonIsNonRetryable() {
        assertThatThrownBy(() -> listener.onOrderPlaced(record("{ not json"), acknowledgment))
                .isInstanceOf(NonRetryableMessageException.class);
        verify(acknowledgment, never()).acknowledge();
    }

    @Test
    void aMessageWithNoPayloadIsNonRetryable() {
        String noPayload = """
                {"eventId":"b19d2c5a-8f31-4d0e-9a77-1c3e5f7a9b0d","eventType":"ORDER_PLACED",
                 "eventTime":"2026-09-28T09:14:22Z","source":"trade-api","schemaVersion":1}
                """;

        assertThatThrownBy(() -> listener.onOrderPlaced(record(noPayload), acknowledgment))
                .isInstanceOf(NonRetryableMessageException.class);
    }

    @Test
    void anUnexpectedEventTypeOnTheOrdersTopicIsNonRetryable() {
        String wrongType = VALID_MESSAGE.replace("ORDER_PLACED", "ORDER_FILLED");

        assertThatThrownBy(() -> listener.onOrderPlaced(record(wrongType), acknowledgment))
                .isInstanceOf(NonRetryableMessageException.class);
    }

    private static ConsumerRecord<String, String> record(String value) {
        return new ConsumerRecord<>("orders", 0, 42L, "1", value);
    }

    private static TradeEventEnvelope envelope() {
        TradeEventPayload payload = new TradeEventPayload(
                ORDER_ID, 1L, "AAPL", Side.BUY, 100, new BigDecimal("233.00"),
                new BigDecimal("232.71"), OrderStatus.FILLED, null, new BigDecimal("-23271.00"),
                300, new BigDecimal("229.57"), "2026-09-28T09:14:24Z");
        return new TradeEventEnvelope("d47f9a10-3e2b-4c88-b0a1-7e6d5c4b3a29",
                TradeEventEnvelope.ORDER_FILLED, "2026-09-28T09:14:24Z",
                TradeEventEnvelope.SOURCE, TradeEventEnvelope.SCHEMA_VERSION, payload);
    }
}

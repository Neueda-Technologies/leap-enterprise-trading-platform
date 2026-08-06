package com.neueda.trading.executor.execution;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.neueda.trading.executor.config.ExecutorProperties;
import com.neueda.trading.executor.domain.OrderStatus;
import com.neueda.trading.executor.domain.Side;
import com.neueda.trading.executor.messaging.NonRetryableMessageException;
import com.neueda.trading.executor.messaging.OrderPlacedPayload;
import com.neueda.trading.executor.messaging.TradeEventEnvelope;
import com.neueda.trading.executor.messaging.TradeEventPayload;
import com.neueda.trading.executor.persistence.AccountRow;
import com.neueda.trading.executor.persistence.ExecutionRepository;
import com.neueda.trading.executor.persistence.OptimisticLockConflictException;
import com.neueda.trading.executor.persistence.OrderRow;
import com.neueda.trading.executor.persistence.PositionRow;
import com.neueda.trading.executor.quote.Quote;
import com.neueda.trading.executor.quote.QuoteClient;
import com.neueda.trading.executor.support.DirectTransactionTemplate;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

/**
 * The executor's behaviour with the quote client and the repository replaced by mocks.
 *
 * <p>Three properties are worth more than the rest and are tested hardest: an order that is no
 * longer NEW moves no money, a rejection is still an event, and a lost optimistic lock is retried
 * rather than failed.
 */
class OrderExecutionServiceTest {

    private static final UUID ORDER_ID = UUID.fromString("6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e");
    private static final long ACCOUNT_ID = 1L;
    private static final String SYMBOL = "AAPL";
    private static final Instant NOW = Instant.parse("2026-09-28T09:14:24Z");

    private final ExecutionRepository repository = mock(ExecutionRepository.class);
    private final QuoteClient quoteClient = mock(QuoteClient.class);
    private final ExecutorProperties properties = new ExecutorProperties();

    private OrderExecutionService service;

    @BeforeEach
    void setUp() {
        service = new OrderExecutionService(
                repository,
                quoteClient,
                DirectTransactionTemplate.create(),
                new ExecutionLatency(Duration.ZERO, Duration.ZERO),
                properties,
                Clock.fixed(NOW, ZoneOffset.UTC));

        when(repository.isTradable(SYMBOL)).thenReturn(true);
        when(repository.findAccount(ACCOUNT_ID))
                .thenReturn(Optional.of(new AccountRow(ACCOUNT_ID, money("50000.00"), "ACTIVE", 7)));
        when(repository.findPosition(ACCOUNT_ID, SYMBOL))
                .thenReturn(new PositionRow(ACCOUNT_ID, SYMBOL, 200, money("228.00")));
        when(repository.markFilled(any(), any(), any())).thenReturn(1);
        when(repository.markRejected(any(), anyString(), any())).thenReturn(1);
        givenQuote("232.7149");
    }

    @Nested
    @DisplayName("filling")
    class Filling {

        @Test
        void aBuyDebitsCashAndRaisesThePositionAtTheWeightedAverageCost() {
            givenOrder(Side.BUY, 100, "233.00", OrderStatus.NEW);

            TradeEventPayload event = executeAndExpectEvent(TradeEventEnvelope.ORDER_FILLED);

            verify(repository).markFilled(eq(ORDER_ID), eq(money("232.71")), eq(NOW));
            // 50000.00 less 100 at 232.71.
            verify(repository).updateCashBalance(ACCOUNT_ID, money("26729.00"), 7, NOW);
            // (200 * 228.00 + 100 * 232.71) / 300.
            verify(repository).upsertPosition(ACCOUNT_ID, SYMBOL, 300, money("229.57"));

            assertThat(event.status()).isEqualTo(OrderStatus.FILLED);
            assertThat(event.executedPrice()).isEqualByComparingTo("232.71");
            assertThat(event.cashDelta()).isEqualByComparingTo("-23271.00");
            assertThat(event.positionQuantityAfter()).isEqualTo(300);
            assertThat(event.averageCostAfter()).isEqualByComparingTo("229.57");
            assertThat(event.reason()).isNull();
            assertThat(event.executedOn()).isEqualTo("2026-09-28T09:14:24Z");
        }

        @Test
        void aSellCreditsCashAndLeavesTheAverageCostAlone() {
            givenOrder(Side.SELL, 100, "230.00", OrderStatus.NEW);

            TradeEventPayload event = executeAndExpectEvent(TradeEventEnvelope.ORDER_FILLED);

            verify(repository).markFilled(eq(ORDER_ID), eq(money("232.71")), eq(NOW));
            verify(repository).updateCashBalance(ACCOUNT_ID, money("73271.00"), 7, NOW);
            verify(repository).upsertPosition(ACCOUNT_ID, SYMBOL, 100, money("228.00"));

            assertThat(event.cashDelta()).isEqualByComparingTo("23271.00");
            assertThat(event.averageCostAfter()).isEqualByComparingTo("228.00");
        }

        @Test
        void closingAHoldingResetsTheAverageCostSoTheNextBuyStartsClean() {
            when(repository.findPosition(ACCOUNT_ID, SYMBOL))
                    .thenReturn(new PositionRow(ACCOUNT_ID, SYMBOL, 100, money("228.00")));
            givenOrder(Side.SELL, 100, "230.00", OrderStatus.NEW);

            TradeEventPayload event = executeAndExpectEvent(TradeEventEnvelope.ORDER_FILLED);

            verify(repository).upsertPosition(ACCOUNT_ID, SYMBOL, 0, money("0.00"));
            assertThat(event.positionQuantityAfter()).isZero();
            assertThat(event.averageCostAfter()).isEqualByComparingTo("0.00");
        }

        @Test
        void theEventCarriesTheContractedEnvelope() {
            givenOrder(Side.BUY, 100, "233.00", OrderStatus.NEW);

            TradeEventEnvelope envelope = service.execute(message()).orElseThrow();

            assertThat(envelope.source()).isEqualTo("trade-executor");
            assertThat(envelope.schemaVersion()).isEqualTo(1);
            assertThat(envelope.eventTime()).isEqualTo("2026-09-28T09:14:24Z");
            assertThat(UUID.fromString(envelope.eventId())).isNotNull();
        }
    }

    @Nested
    @DisplayName("rejecting")
    class Rejecting {

        @Test
        void anUnavailableQuoteRejectsTheOrderRatherThanLeavingItWorking() {
            when(quoteClient.quoteFor(SYMBOL)).thenReturn(Optional.empty());
            givenOrder(Side.BUY, 100, "233.00", OrderStatus.NEW);

            TradeEventPayload event = executeAndExpectEvent(TradeEventEnvelope.ORDER_REJECTED);

            verify(repository).markRejected(ORDER_ID, "PRICING_UNAVAILABLE", NOW);
            verify(repository, never()).updateCashBalance(anyLong(), any(), anyInt(), any());
            verify(repository, never()).upsertPosition(anyLong(), anyString(), anyInt(), any());
            assertThat(event.status()).isEqualTo(OrderStatus.REJECTED);
            assertThat(event.executedPrice()).isNull();
            assertThat(event.reason()).isEqualTo("PRICING_UNAVAILABLE");
        }

        @Test
        void aRejectionReportsTheUnchangedPositionSoAConsumerCanApplyEveryEvent() {
            when(quoteClient.quoteFor(SYMBOL)).thenReturn(Optional.empty());
            givenOrder(Side.BUY, 100, "233.00", OrderStatus.NEW);

            TradeEventPayload event = executeAndExpectEvent(TradeEventEnvelope.ORDER_REJECTED);

            assertThat(event.cashDelta()).isEqualByComparingTo("0.00");
            assertThat(event.positionQuantityAfter()).isEqualTo(200);
            assertThat(event.averageCostAfter()).isEqualByComparingTo("228.00");
        }

        @Test
        void aBuyAboveTheLimitPriceIsRejected() {
            givenQuote("233.01");
            givenOrder(Side.BUY, 100, "233.00", OrderStatus.NEW);

            executeAndExpectEvent(TradeEventEnvelope.ORDER_REJECTED);

            verify(repository).markRejected(ORDER_ID, "PRICE_NOT_MET", NOW);
        }

        @Test
        void aSellBelowTheLimitPriceIsRejected() {
            givenQuote("229.99");
            givenOrder(Side.SELL, 100, "230.00", OrderStatus.NEW);

            executeAndExpectEvent(TradeEventEnvelope.ORDER_REJECTED);

            verify(repository).markRejected(ORDER_ID, "PRICE_NOT_MET", NOW);
        }

        @Test
        void anInstrumentSuspendedAfterAcceptanceIsRejectedWithoutSpendingAQuote() {
            when(repository.isTradable(SYMBOL)).thenReturn(false);
            givenOrder(Side.BUY, 100, "233.00", OrderStatus.NEW);

            executeAndExpectEvent(TradeEventEnvelope.ORDER_REJECTED);

            verify(repository).markRejected(ORDER_ID, "INSTRUMENT_NOT_TRADABLE", NOW);
            verifyNoInteractions(quoteClient);
        }

        @Test
        void cashSpentBetweenAcceptanceAndExecutionIsRejected() {
            when(repository.findAccount(ACCOUNT_ID))
                    .thenReturn(Optional.of(new AccountRow(ACCOUNT_ID, money("100.00"), "ACTIVE", 7)));
            givenOrder(Side.BUY, 100, "233.00", OrderStatus.NEW);

            executeAndExpectEvent(TradeEventEnvelope.ORDER_REJECTED);

            verify(repository).markRejected(ORDER_ID, "INSUFFICIENT_FUNDS", NOW);
            verify(repository, never()).updateCashBalance(anyLong(), any(), anyInt(), any());
        }

        @Test
        void aHoldingSoldBetweenAcceptanceAndExecutionIsRejected() {
            when(repository.findPosition(ACCOUNT_ID, SYMBOL))
                    .thenReturn(new PositionRow(ACCOUNT_ID, SYMBOL, 10, money("228.00")));
            givenOrder(Side.SELL, 100, "230.00", OrderStatus.NEW);

            executeAndExpectEvent(TradeEventEnvelope.ORDER_REJECTED);

            verify(repository).markRejected(ORDER_ID, "INSUFFICIENT_HOLDINGS", NOW);
        }

        @Test
        void anAccountSuspendedAfterAcceptanceIsRejected() {
            when(repository.findAccount(ACCOUNT_ID))
                    .thenReturn(Optional.of(new AccountRow(ACCOUNT_ID, money("50000.00"), "SUSPENDED", 7)));
            givenOrder(Side.BUY, 100, "233.00", OrderStatus.NEW);

            executeAndExpectEvent(TradeEventEnvelope.ORDER_REJECTED);

            verify(repository).markRejected(ORDER_ID, "ACCOUNT_NOT_ACTIVE", NOW);
        }
    }

    @Nested
    @DisplayName("idempotency")
    class Idempotency {

        @Test
        void anOrderThatIsNoLongerNewIsDroppedWithoutTouchingAnything() {
            givenOrder(Side.BUY, 100, "233.00", OrderStatus.FILLED);

            assertThat(service.execute(message())).isEmpty();

            verifyNoInteractions(quoteClient);
            verify(repository, never()).markFilled(any(), any(), any());
            verify(repository, never()).markRejected(any(), anyString(), any());
            verify(repository, never()).updateCashBalance(anyLong(), any(), anyInt(), any());
        }

        @Test
        void aCancelledOrderIsDropped() {
            givenOrder(Side.BUY, 100, "233.00", OrderStatus.CANCELLED);

            assertThat(service.execute(message())).isEmpty();

            verify(repository, never()).markFilled(any(), any(), any());
        }

        @Test
        void losingTheGuardedTransitionToAConcurrentDeliveryMovesNoMoney() {
            // Two consumers reached the same NEW order. The other one won the UPDATE.
            when(repository.markFilled(any(), any(), any())).thenReturn(0);
            givenOrder(Side.BUY, 100, "233.00", OrderStatus.NEW);

            assertThat(service.execute(message())).isEmpty();

            verify(repository, never()).updateCashBalance(anyLong(), any(), anyInt(), any());
            verify(repository, never()).upsertPosition(anyLong(), anyString(), anyInt(), any());
        }

        @Test
        void losingTheGuardedTransitionOnARejectPublishesNothing() {
            when(repository.markRejected(any(), anyString(), any())).thenReturn(0);
            when(quoteClient.quoteFor(SYMBOL)).thenReturn(Optional.empty());
            givenOrder(Side.BUY, 100, "233.00", OrderStatus.NEW);

            assertThat(service.execute(message())).isEmpty();
        }

        @Test
        void anOrderIdentifierThatIsNotInPostgresIsAPoisonMessage() {
            when(repository.findOrder(ORDER_ID)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.execute(message()))
                    .isInstanceOf(NonRetryableMessageException.class);
        }
    }

    @Nested
    @DisplayName("optimistic locking")
    class OptimisticLocking {

        @Test
        void aLostLockIsRetriedAndTheSecondAttemptSucceeds() {
            doThrow(new OptimisticLockConflictException(ACCOUNT_ID, 7))
                    .doNothing()
                    .when(repository).updateCashBalance(anyLong(), any(), anyInt(), any());
            givenOrder(Side.BUY, 100, "233.00", OrderStatus.NEW);

            executeAndExpectEvent(TradeEventEnvelope.ORDER_FILLED);

            verify(repository, times(2)).updateCashBalance(anyLong(), any(), anyInt(), any());
        }

        @Test
        void anExhaustedRetryBudgetFailsTheMessageSoKafkaRedeliversIt() {
            properties.getOptimisticLock().setMaxAttempts(2);
            properties.getOptimisticLock().setBackoff(Duration.ZERO);
            doThrow(new OptimisticLockConflictException(ACCOUNT_ID, 7))
                    .when(repository).updateCashBalance(anyLong(), any(), anyInt(), any());
            givenOrder(Side.BUY, 100, "233.00", OrderStatus.NEW);

            assertThatThrownBy(() -> service.execute(message()))
                    .isInstanceOf(OptimisticLockConflictException.class);

            verify(repository, times(2)).updateCashBalance(anyLong(), any(), anyInt(), any());
        }

        @Test
        void theExpectedVersionCarriedIntoTheUpdateIsTheOneThatWasRead() {
            doNothing().when(repository).updateCashBalance(anyLong(), any(), anyInt(), any());
            givenOrder(Side.BUY, 100, "233.00", OrderStatus.NEW);

            service.execute(message());

            verify(repository).updateCashBalance(eq(ACCOUNT_ID), any(), eq(7), eq(NOW));
        }
    }

    private TradeEventPayload executeAndExpectEvent(String expectedEventType) {
        TradeEventEnvelope envelope = service.execute(message()).orElseThrow(
                () -> new AssertionError("Expected an event of type " + expectedEventType));
        assertThat(envelope.eventType()).isEqualTo(expectedEventType);
        return envelope.payload();
    }

    private void givenOrder(Side side, int quantity, String limitPrice, OrderStatus status) {
        when(repository.findOrder(ORDER_ID)).thenReturn(Optional.of(new OrderRow(
                ORDER_ID, ACCOUNT_ID, SYMBOL, side, quantity, money(limitPrice), status)));
    }

    private void givenQuote(String price) {
        when(quoteClient.quoteFor(SYMBOL)).thenReturn(Optional.of(
                new Quote(SYMBOL, money(price), "USD", NOW, "open", false)));
    }

    /**
     * The same message body serves every test. Only the identifier is read from it: the executor
     * settles the order row it finds in Postgres, not the copy of the order carried on the topic.
     * A message whose body disagreed with the row would otherwise be a way to trade something the
     * Trade REST API never validated.
     */
    private OrderPlacedPayload message() {
        return new OrderPlacedPayload(ORDER_ID, ACCOUNT_ID, SYMBOL, Side.BUY, 100,
                money("233.00"), ORDER_ID.toString(), "2026-09-28T09:14:22Z");
    }

    private static BigDecimal money(String value) {
        return new BigDecimal(value);
    }
}

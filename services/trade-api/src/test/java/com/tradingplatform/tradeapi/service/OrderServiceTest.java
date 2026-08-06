package com.tradingplatform.tradeapi.service;

import com.tradingplatform.domain.exception.AccountNotActiveException;
import com.tradingplatform.domain.exception.AccountNotFoundException;
import com.tradingplatform.domain.exception.DuplicateOrderException;
import com.tradingplatform.domain.exception.InstrumentNotFoundException;
import com.tradingplatform.domain.exception.InsufficientFundsException;
import com.tradingplatform.domain.exception.InsufficientHoldingsException;
import com.tradingplatform.domain.model.Account;
import com.tradingplatform.domain.model.AccountStatus;
import com.tradingplatform.domain.model.Order;
import com.tradingplatform.domain.model.OrderSide;
import com.tradingplatform.domain.model.OrderStatus;
import com.tradingplatform.domain.service.OrderPlacementService;
import com.tradingplatform.domain.service.SettlementService;
import com.tradingplatform.tradeapi.TestData;
import com.tradingplatform.tradeapi.config.ExecutionMode;
import com.tradingplatform.tradeapi.messaging.OrderPlacedPayload;
import com.tradingplatform.tradeapi.messaging.TradeEventPayload;
import com.tradingplatform.tradeapi.repository.AccountMapper;
import com.tradingplatform.tradeapi.repository.InstrumentMapper;
import com.tradingplatform.tradeapi.repository.OrderMapper;
import com.tradingplatform.tradeapi.repository.PositionMapper;
import com.tradingplatform.tradeapi.security.AccountAccessDeniedException;
import com.tradingplatform.tradeapi.web.dto.OrderResponse;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DuplicateKeyException;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.ZoneOffset;

import static com.tradingplatform.tradeapi.TestData.ACCOUNT_ID;
import static com.tradingplatform.tradeapi.TestData.NOW;
import static com.tradingplatform.tradeapi.TestData.SYMBOL;
import static com.tradingplatform.tradeapi.TestData.account;
import static com.tradingplatform.tradeapi.TestData.customer;
import static com.tradingplatform.tradeapi.TestData.customerOf;
import static com.tradingplatform.tradeapi.TestData.instrument;
import static com.tradingplatform.tradeapi.TestData.money;
import static com.tradingplatform.tradeapi.TestData.position;
import static com.tradingplatform.tradeapi.TestData.request;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * The order service, with the mappers mocked.
 *
 * <p>The domain services are the real ones. Mocking them would test that the service calls something,
 * which is not the question: the question is whether a request that breaks a rule produces the right
 * exception, and only the real rules can answer it.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("OrderService")
class OrderServiceTest {

    @Mock private AccountMapper accountMapper;
    @Mock private InstrumentMapper instrumentMapper;
    @Mock private OrderMapper orderMapper;
    @Mock private PositionMapper positionMapper;
    @Mock private ApplicationEventPublisher events;

    private final Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);

    private OrderService serviceIn(ExecutionMode mode) {
        return new OrderService(
                accountMapper, instrumentMapper, orderMapper, positionMapper,
                new OrderPlacementService(), new SettlementService(),
                events, TestData.properties(mode), clock);
    }

    private void givenAccount(Account account) {
        when(accountMapper.findById(ACCOUNT_ID)).thenReturn(account);
    }

    private void givenTradableInstrument() {
        when(instrumentMapper.findBySymbol(SYMBOL)).thenReturn(instrument());
    }

    @Nested
    @DisplayName("asynchronous execution, Sprint 7 onwards")
    class Async {

        private OrderService service;

        @org.junit.jupiter.api.BeforeEach
        void setUp() {
            service = serviceIn(ExecutionMode.ASYNC);
        }

        @Test
        @DisplayName("an accepted order is recorded as NEW and published, and no money moves")
        void testPlaceOrder_ReturnsNewAndPublishes() {
            givenAccount(account("10000.00"));
            givenTradableInstrument();

            OrderResponse response = service.placeOrder(request(OrderSide.BUY, 100, "25.50"), customer());

            assertEquals(OrderStatus.NEW, response.status());
            assertEquals("Order accepted", response.message());
            assertTrue(response.orderId().startsWith("ORD-"));

            verify(orderMapper).insert(any(Order.class));
            verify(events).publishEvent(any(OrderPlacedPayload.class));
            verify(accountMapper, never()).updateCashBalance(anyLong(), any(), anyInt(), any());
            verify(positionMapper, never()).upsert(anyLong(), anyString(), anyInt(), any());
        }

        @Test
        @DisplayName("the published payload carries the order, keyed for the orders topic")
        void testPlaceOrder_PublishesTheContractedPayload() {
            givenAccount(account("10000.00"));
            givenTradableInstrument();

            service.placeOrder(request(OrderSide.BUY, 100, "25.50"), customer());

            ArgumentCaptor<OrderPlacedPayload> captor =
                    ArgumentCaptor.forClass(OrderPlacedPayload.class);
            verify(events).publishEvent(captor.capture());

            OrderPlacedPayload payload = captor.getValue();
            assertEquals(ACCOUNT_ID, payload.accountId());
            assertEquals(SYMBOL, payload.symbol());
            assertEquals(OrderSide.BUY, payload.side());
            assertEquals(100, payload.quantity());
            assertEquals(0, payload.price().compareTo(money("25.50")));
            assertEquals(TestData.IDEMPOTENCY_KEY, payload.idempotencyKey());
            assertEquals(NOW, payload.createdOn());
        }

        @Test
        @DisplayName("a sell is recorded against the holding without touching it")
        void testPlaceOrder_Sell() {
            givenAccount(account("0.00"));
            givenTradableInstrument();
            when(positionMapper.find(ACCOUNT_ID, SYMBOL)).thenReturn(position(100, "20.00"));

            OrderResponse response = service.placeOrder(request(OrderSide.SELL, 40, "25.50"), customer());

            assertEquals(OrderStatus.NEW, response.status());
            verify(positionMapper, never()).upsert(anyLong(), anyString(), anyInt(), any());
        }
    }

    @Nested
    @DisplayName("synchronous execution, Sprint 6")
    class Sync {

        private OrderService service;

        @org.junit.jupiter.api.BeforeEach
        void setUp() {
            service = serviceIn(ExecutionMode.SYNC);
        }

        @Test
        @DisplayName("a buy fills in process, debiting cash and writing the position")
        void testPlaceOrder_FillsImmediately() {
            givenAccount(account("10000.00"));
            givenTradableInstrument();
            when(accountMapper.updateCashBalance(eq(ACCOUNT_ID), any(), eq(0), any())).thenReturn(1);
            when(orderMapper.fillIfNew(any(), any(), any())).thenReturn(1);

            OrderResponse response = service.placeOrder(request(OrderSide.BUY, 100, "25.50"), customer());

            assertEquals(OrderStatus.FILLED, response.status());
            assertEquals("Order executed", response.message());

            ArgumentCaptor<BigDecimal> balance = ArgumentCaptor.forClass(BigDecimal.class);
            verify(accountMapper).updateCashBalance(eq(ACCOUNT_ID), balance.capture(), eq(0), any());
            assertEquals(0, balance.getValue().compareTo(money("7450.00")));

            verify(positionMapper).upsert(ACCOUNT_ID, SYMBOL, 100, money("25.50"));
            verify(orderMapper).fillIfNew(any(), any(), any());
            verify(events).publishEvent(any(TradeEventPayload.class));
        }

        @Test
        @DisplayName("a sell credits cash and reduces the holding, leaving the cost basis alone")
        void testPlaceOrder_SellFillsImmediately() {
            givenAccount(account("100.00"));
            givenTradableInstrument();
            when(positionMapper.find(ACCOUNT_ID, SYMBOL)).thenReturn(position(100, "20.00"));
            when(accountMapper.updateCashBalance(eq(ACCOUNT_ID), any(), eq(0), any())).thenReturn(1);
            when(orderMapper.fillIfNew(any(), any(), any())).thenReturn(1);

            OrderResponse response = service.placeOrder(request(OrderSide.SELL, 40, "25.50"), customer());

            assertEquals(OrderStatus.FILLED, response.status());
            verify(accountMapper).updateCashBalance(eq(ACCOUNT_ID), eq(money("1120.00")), eq(0), any());
            verify(positionMapper).upsert(ACCOUNT_ID, SYMBOL, 60, money("20.00"));
        }

        @Test
        @DisplayName("the update is guarded on the version the account was read at")
        void testPlaceOrder_UsesTheLoadedVersion() {
            givenAccount(account("10000.00", AccountStatus.ACTIVE, 7));
            givenTradableInstrument();
            when(accountMapper.updateCashBalance(eq(ACCOUNT_ID), any(), eq(7), any())).thenReturn(1);
            when(orderMapper.fillIfNew(any(), any(), any())).thenReturn(1);

            service.placeOrder(request(OrderSide.BUY, 1, "25.50"), customer());

            verify(accountMapper).updateCashBalance(eq(ACCOUNT_ID), any(), eq(7), any());
        }

        @Test
        @DisplayName("losing the optimistic lock is a conflict, never a silent overwrite")
        void testPlaceOrder_OptimisticLockLost() {
            givenAccount(account("10000.00"));
            givenTradableInstrument();
            when(accountMapper.updateCashBalance(anyLong(), any(), anyInt(), any())).thenReturn(0);

            ConcurrentUpdateException thrown = assertThrows(ConcurrentUpdateException.class,
                    () -> service.placeOrder(request(OrderSide.BUY, 100, "25.50"), customer()));

            assertEquals("ORD-409", ConcurrentUpdateException.ERROR_CODE);
            assertTrue(thrown.detail().contains("accounts.version"));
            verify(positionMapper, never()).upsert(anyLong(), anyString(), anyInt(), any());
        }

        @Test
        @DisplayName("an order that another process already resolved is a conflict too")
        void testPlaceOrder_GuardedFillLost() {
            givenAccount(account("10000.00"));
            givenTradableInstrument();
            when(accountMapper.updateCashBalance(anyLong(), any(), anyInt(), any())).thenReturn(1);
            when(orderMapper.fillIfNew(any(), any(), any())).thenReturn(0);

            assertThrows(ConcurrentUpdateException.class,
                    () -> service.placeOrder(request(OrderSide.BUY, 100, "25.50"), customer()));
        }
    }

    @Nested
    @DisplayName("business rules reach the caller as their own exceptions")
    class Rules {

        private OrderService service;

        @org.junit.jupiter.api.BeforeEach
        void setUp() {
            service = serviceIn(ExecutionMode.ASYNC);
        }

        @Test
        void testPlaceOrder_UnknownAccount() {
            givenAccount(null);
            givenTradableInstrument();

            assertThrows(AccountNotFoundException.class,
                    () -> service.placeOrder(request(OrderSide.BUY, 100, "25.50"), customer()));
            verify(orderMapper, never()).insert(any());
        }

        @Test
        void testPlaceOrder_InactiveAccount() {
            givenAccount(account("10000.00", AccountStatus.SUSPENDED, 0));
            givenTradableInstrument();

            assertThrows(AccountNotActiveException.class,
                    () -> service.placeOrder(request(OrderSide.BUY, 100, "25.50"), customer()));
        }

        @Test
        void testPlaceOrder_UnknownInstrument() {
            givenAccount(account("10000.00"));
            when(instrumentMapper.findBySymbol(SYMBOL)).thenReturn(null);

            assertThrows(InstrumentNotFoundException.class,
                    () -> service.placeOrder(request(OrderSide.BUY, 100, "25.50"), customer()));
        }

        @Test
        void testPlaceOrder_InsufficientFunds() {
            givenAccount(account("10.00"));
            givenTradableInstrument();

            assertThrows(InsufficientFundsException.class,
                    () -> service.placeOrder(request(OrderSide.BUY, 100, "25.50"), customer()));
        }

        @Test
        void testPlaceOrder_InsufficientHoldings() {
            givenAccount(account("10000.00"));
            givenTradableInstrument();
            when(positionMapper.find(ACCOUNT_ID, SYMBOL)).thenReturn(position(10, "20.00"));

            assertThrows(InsufficientHoldingsException.class,
                    () -> service.placeOrder(request(OrderSide.SELL, 100, "25.50"), customer()));
        }

        @Test
        @DisplayName("business rule 8 arrives as a unique constraint violation, not as a lookup")
        void testPlaceOrder_DuplicateIdempotencyKey() {
            givenAccount(account("10000.00"));
            givenTradableInstrument();
            when(orderMapper.insert(any())).thenThrow(new DuplicateKeyException("uq_orders_idempotency_key"));

            DuplicateOrderException thrown = assertThrows(DuplicateOrderException.class,
                    () -> service.placeOrder(request(OrderSide.BUY, 100, "25.50"), customer()));

            assertEquals("ORD-409", thrown.errorCode());
            assertEquals("Duplicate order", thrown.getMessage());
            verify(events, never()).publishEvent(any(OrderPlacedPayload.class));
        }
    }

    @Nested
    @DisplayName("authorisation")
    class Authorisation {

        private OrderService service;

        @org.junit.jupiter.api.BeforeEach
        void setUp() {
            service = serviceIn(ExecutionMode.ASYNC);
        }

        @Test
        @DisplayName("a token for another account cannot place an order, and nothing is read")
        void testPlaceOrder_ForeignAccount() {
            assertThrows(AccountAccessDeniedException.class,
                    () -> service.placeOrder(request(OrderSide.BUY, 100, "25.50"), customerOf(2L)));

            verifyNoInteractions(accountMapper, instrumentMapper, orderMapper, positionMapper);
        }

        @Test
        @DisplayName("an ADMIN token reaches any account")
        void testPlaceOrder_AdminReachesAnyAccount() {
            givenAccount(account("10000.00"));
            givenTradableInstrument();

            var admin = new com.tradingplatform.tradeapi.security.AuthenticatedUser(
                    "operator", 999L, java.util.List.of("ADMIN"), "auth-service");

            OrderResponse response = service.placeOrder(request(OrderSide.BUY, 1, "25.50"), admin);

            assertEquals(OrderStatus.NEW, response.status());
        }
    }

    @Nested
    @DisplayName("cancellation")
    class Cancellation {

        private OrderService service;

        @org.junit.jupiter.api.BeforeEach
        void setUp() {
            service = serviceIn(ExecutionMode.ASYNC);
        }

        @Test
        void testCancelOrder_Cancels() {
            when(orderMapper.findById(TestData.ORDER_ID)).thenReturn(TestData.order(OrderStatus.NEW));
            givenAccount(account("10000.00"));
            when(orderMapper.cancelIfNew(TestData.ORDER_ID)).thenReturn(1);

            OrderResponse response = service.cancelOrder(TestData.ORDER_ID, customer());

            assertEquals(OrderStatus.CANCELLED, response.status());
            assertEquals("Order cancelled", response.message());
        }

        @Test
        @DisplayName("a cancellation is an event, carrying the customer reason")
        void testCancelOrder_PublishesTradeEvent() {
            when(orderMapper.findById(TestData.ORDER_ID)).thenReturn(TestData.order(OrderStatus.NEW));
            givenAccount(account("10000.00"));
            when(orderMapper.cancelIfNew(TestData.ORDER_ID)).thenReturn(1);

            service.cancelOrder(TestData.ORDER_ID, customer());

            ArgumentCaptor<TradeEventPayload> captor = ArgumentCaptor.forClass(TradeEventPayload.class);
            verify(events).publishEvent(captor.capture());

            TradeEventPayload payload = captor.getValue();
            assertEquals(OrderStatus.CANCELLED, payload.status());
            assertEquals("CANCELLED_BY_CUSTOMER", payload.reason());
            assertEquals("ORDER_CANCELLED", payload.eventType());
            assertEquals(0, payload.cashDelta().signum());
        }

        @Test
        void testCancelOrder_UnknownOrder() {
            when(orderMapper.findById(TestData.ORDER_ID)).thenReturn(null);

            assertThrows(com.tradingplatform.domain.exception.OrderNotFoundException.class,
                    () -> service.cancelOrder(TestData.ORDER_ID, customer()));
        }

        @Test
        @DisplayName("zero rows from the guarded update means the order was already resolved")
        void testCancelOrder_NotCancellable() {
            when(orderMapper.findById(TestData.ORDER_ID)).thenReturn(TestData.order(OrderStatus.NEW));
            givenAccount(account("10000.00"));
            when(orderMapper.cancelIfNew(TestData.ORDER_ID)).thenReturn(0);

            assertThrows(com.tradingplatform.domain.exception.OrderNotCancellableException.class,
                    () -> service.cancelOrder(TestData.ORDER_ID, customer()));
            verify(events, never()).publishEvent(any(TradeEventPayload.class));
        }

        @Test
        @DisplayName("business rule 2 applies to cancelling as well as to placing")
        void testCancelOrder_InactiveAccount() {
            when(orderMapper.findById(TestData.ORDER_ID)).thenReturn(TestData.order(OrderStatus.NEW));
            givenAccount(account("10000.00", AccountStatus.CLOSED, 0));

            assertThrows(AccountNotActiveException.class,
                    () -> service.cancelOrder(TestData.ORDER_ID, customer()));
            verify(orderMapper, never()).cancelIfNew(any());
        }

        @Test
        void testCancelOrder_ForeignAccount() {
            when(orderMapper.findById(TestData.ORDER_ID)).thenReturn(TestData.order(OrderStatus.NEW));

            assertThrows(AccountAccessDeniedException.class,
                    () -> service.cancelOrder(TestData.ORDER_ID, customerOf(2L)));
            verify(orderMapper, never()).cancelIfNew(any());
        }
    }
}

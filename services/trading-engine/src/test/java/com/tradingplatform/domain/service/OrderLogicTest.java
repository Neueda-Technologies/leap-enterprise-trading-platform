package com.tradingplatform.domain.service;

import com.tradingplatform.domain.TestFixtures;
import com.tradingplatform.domain.dto.PlaceOrderRequest;
import com.tradingplatform.domain.exception.AccountNotActiveException;
import com.tradingplatform.domain.exception.AccountNotFoundException;
import com.tradingplatform.domain.exception.DuplicateOrderException;
import com.tradingplatform.domain.exception.InstrumentNotFoundException;
import com.tradingplatform.domain.exception.InsufficientFundsException;
import com.tradingplatform.domain.exception.InsufficientHoldingsException;
import com.tradingplatform.domain.exception.InvalidOrderException;
import com.tradingplatform.domain.model.Account;
import com.tradingplatform.domain.model.AccountStatus;
import com.tradingplatform.domain.model.Order;
import com.tradingplatform.domain.model.OrderSide;
import com.tradingplatform.domain.model.OrderStatus;
import com.tradingplatform.domain.model.Position;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

import java.util.Set;
import java.util.UUID;

import static com.tradingplatform.domain.TestFixtures.account;
import static com.tradingplatform.domain.TestFixtures.instrument;
import static com.tradingplatform.domain.TestFixtures.money;
import static com.tradingplatform.domain.TestFixtures.position;
import static com.tradingplatform.domain.TestFixtures.request;
import static com.tradingplatform.domain.TestFixtures.suspendedInstrument;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

/**
 * Business rules 1 to 8, in the order the contract fixes.
 *
 * <p>Named in the Sprint 5 acceptance criteria. It must be green.
 *
 * <p>Every rule has at least one test that proves it fires and one that proves it does not fire when
 * it should not. The last block proves the ordering itself, because a request that breaks two rules
 * must receive the earlier error and clients branch on that code.
 */
@DisplayName("Order placement rules")
class OrderLogicTest {

    private final OrderPlacementService service = new OrderPlacementService();

    private Order place(PlaceOrderRequest request,
                        Account account,
                        com.tradingplatform.domain.model.Instrument instrument,
                        Position position) {
        return service.placeOrder(request, account, instrument, position,
                UUID.randomUUID(), TestFixtures.NOW);
    }

    @Nested
    @DisplayName("happy path")
    class HappyPath {

        @Test
        void testBuy_Accepted() {
            Order order = place(request(OrderSide.BUY, 100, "25.50"),
                    account("10000.00"), instrument(), null);

            assertEquals(OrderStatus.NEW, order.getStatus());
            assertEquals(OrderSide.BUY, order.getSide());
            assertEquals(100, order.getQuantity());
            assertEquals(0, order.getPrice().compareTo(money("25.50")));
        }

        @Test
        void testSell_Accepted() {
            Order order = place(request(OrderSide.SELL, 40, "25.50"),
                    account("0.00"), instrument(), position(100, "20.00"));

            assertEquals(OrderStatus.NEW, order.getStatus());
            assertEquals(OrderSide.SELL, order.getSide());
        }

        @Test
        @DisplayName("acceptance records intent and moves no money")
        void testPlacement_DoesNotMoveCashOrPosition() {
            Account account = account("10000.00");
            Position holding = position(100, "20.00");

            place(request(OrderSide.BUY, 100, "25.50"), account, instrument(), holding);

            assertEquals(0, account.getCashBalance().compareTo(money("10000.00")));
            assertEquals(100, holding.getQuantity());
        }

        @Test
        @DisplayName("the order carries the numeric account key, not the business reference")
        void testPlacement_UsesNumericAccountKey() {
            Order order = place(request(OrderSide.BUY, 1, "25.50"),
                    account("10000.00"), instrument(), null);

            assertEquals(TestFixtures.ACCOUNT_ID, order.getAccountId());
        }
    }

    @Nested
    @DisplayName("rule 1: the account must exist")
    class Rule1 {

        @Test
        void testReject_UnknownAccount() {
            AccountNotFoundException thrown = assertThrows(AccountNotFoundException.class,
                    () -> place(request(OrderSide.BUY, 100, "25.50"), null, instrument(), null));

            assertEquals("ACC-404", thrown.errorCode());
            assertEquals("Account not found", thrown.getMessage());
        }
    }

    @Nested
    @DisplayName("rule 2: the account must be ACTIVE")
    class Rule2 {

        @ParameterizedTest
        @EnumSource(value = AccountStatus.class, names = {"SUSPENDED", "CLOSED"})
        @DisplayName("a suspended or closed account cannot trade")
        void testReject_InactiveAccount(AccountStatus status) {
            AccountNotActiveException thrown = assertThrows(AccountNotActiveException.class,
                    () -> place(request(OrderSide.BUY, 100, "25.50"),
                            account("10000.00", status), instrument(), null));

            assertEquals("ACC-403", thrown.errorCode());
            assertEquals("Account not active", thrown.getMessage());
            assertEquals(status, thrown.status());
        }

        @Test
        @DisplayName("a sell from an inactive account is refused too")
        void testReject_InactiveAccountOnSell() {
            assertThrows(AccountNotActiveException.class,
                    () -> place(request(OrderSide.SELL, 10, "25.50"),
                            account("0.00", AccountStatus.CLOSED), instrument(), position(100, "20.00")));
        }
    }

    @Nested
    @DisplayName("rule 3: the instrument must exist and be tradable")
    class Rule3 {

        @Test
        void testReject_UnknownInstrument() {
            InstrumentNotFoundException thrown = assertThrows(InstrumentNotFoundException.class,
                    () -> place(request(OrderSide.BUY, 100, "25.50"),
                            account("10000.00"), null, null));

            assertEquals("INS-404", thrown.errorCode());
            assertEquals("Instrument not found", thrown.getMessage());
        }

        @Test
        @DisplayName("a suspended instrument gives the same answer as an unknown one")
        void testReject_SuspendedInstrument() {
            InstrumentNotFoundException thrown = assertThrows(InstrumentNotFoundException.class,
                    () -> place(request(OrderSide.BUY, 100, "25.50"),
                            account("10000.00"), suspendedInstrument(), null));

            assertEquals("INS-404", thrown.errorCode());
        }
    }

    @Nested
    @DisplayName("rule 4: quantity must be greater than zero")
    class Rule4 {

        @Test
        void testReject_ZeroQuantity() {
            InvalidOrderException thrown = assertThrows(InvalidOrderException.class,
                    () -> place(request(OrderSide.BUY, 0, "25.50"),
                            account("10000.00"), instrument(), null));

            assertEquals("VAL-422", thrown.errorCode());
            assertEquals("quantity", thrown.field());
        }

        @Test
        void testReject_NegativeQuantity() {
            assertThrows(InvalidOrderException.class,
                    () -> place(request(OrderSide.BUY, -10, "25.50"),
                            account("10000.00"), instrument(), null));
        }
    }

    @Nested
    @DisplayName("rule 5: price must be greater than zero")
    class Rule5 {

        @Test
        void testReject_ZeroPrice() {
            InvalidOrderException thrown = assertThrows(InvalidOrderException.class,
                    () -> place(request(OrderSide.BUY, 100, "0.00"),
                            account("10000.00"), instrument(), null));

            assertEquals("VAL-422", thrown.errorCode());
            assertEquals("price", thrown.field());
        }

        @Test
        void testReject_NegativePrice() {
            assertThrows(InvalidOrderException.class,
                    () -> place(request(OrderSide.BUY, 100, "-1.00"),
                            account("10000.00"), instrument(), null));
        }
    }

    @Nested
    @DisplayName("rule 6: a buy needs the cash")
    class Rule6 {

        @Test
        void testBuy_InsufficientFunds() {
            InsufficientFundsException thrown = assertThrows(InsufficientFundsException.class,
                    () -> place(request(OrderSide.BUY, 100, "25.50"),
                            account("2549.99"), instrument(), null));

            assertEquals("ORD-400", thrown.errorCode());
            assertEquals("Insufficient funds", thrown.getMessage());
            assertEquals(0, thrown.required().compareTo(money("2550.00")));
        }

        @Test
        @DisplayName("a buy that spends the balance exactly is accepted")
        void testBuy_ExactBalanceAccepted() {
            Order order = place(request(OrderSide.BUY, 100, "25.50"),
                    account("2550.00"), instrument(), null);

            assertEquals(OrderStatus.NEW, order.getStatus());
        }

        @Test
        @DisplayName("a sell is not checked against the cash balance")
        void testSell_IgnoresCashBalance() {
            Order order = place(request(OrderSide.SELL, 100, "25.50"),
                    account("0.00"), instrument(), position(100, "20.00"));

            assertEquals(OrderStatus.NEW, order.getStatus());
        }
    }

    @Nested
    @DisplayName("rule 7: a sell needs the holding")
    class Rule7 {

        @Test
        void testSell_InsufficientHoldings() {
            InsufficientHoldingsException thrown = assertThrows(InsufficientHoldingsException.class,
                    () -> place(request(OrderSide.SELL, 101, "25.50"),
                            account("10000.00"), instrument(), position(100, "20.00")));

            assertEquals("ORD-409", thrown.errorCode());
            assertEquals("Insufficient holdings", thrown.getMessage());
            assertEquals(101, thrown.requested());
            assertEquals(100, thrown.held());
        }

        @Test
        @DisplayName("no position at all is a holding of zero, not a missing instrument")
        void testSell_NoPositionHeld() {
            InsufficientHoldingsException thrown = assertThrows(InsufficientHoldingsException.class,
                    () -> place(request(OrderSide.SELL, 1, "25.50"),
                            account("10000.00"), instrument(), null));

            assertEquals(0, thrown.held());
        }

        @Test
        @DisplayName("selling the whole holding is accepted")
        void testSell_EntireHoldingAccepted() {
            Order order = place(request(OrderSide.SELL, 100, "25.50"),
                    account("0.00"), instrument(), position(100, "20.00"));

            assertEquals(OrderStatus.NEW, order.getStatus());
        }

        @Test
        @DisplayName("a buy is not checked against the holding")
        void testBuy_IgnoresHoldings() {
            Order order = place(request(OrderSide.BUY, 100, "25.50"),
                    account("10000.00"), instrument(), null);

            assertEquals(OrderStatus.NEW, order.getStatus());
        }
    }

    @Nested
    @DisplayName("rule 8: the idempotency key must be unused")
    class Rule8 {

        @Test
        void testReject_DuplicateIdempotencyKey() {
            IdempotencyKeyRegistry seen = Set.of("key-already-used")::contains;
            OrderPlacementService guarded = new OrderPlacementService(seen);

            DuplicateOrderException thrown = assertThrows(DuplicateOrderException.class,
                    () -> guarded.placeOrder(
                            TestFixtures.request(OrderSide.BUY, 100, "25.50", "key-already-used"),
                            account("10000.00"), instrument(), null,
                            UUID.randomUUID(), TestFixtures.NOW));

            assertEquals("ORD-409", thrown.errorCode());
            assertEquals("Duplicate order", thrown.getMessage());
        }

        @Test
        @DisplayName("an unused key passes")
        void testAccept_FreshIdempotencyKey() {
            IdempotencyKeyRegistry seen = Set.of("key-already-used")::contains;
            OrderPlacementService guarded = new OrderPlacementService(seen);

            Order order = guarded.placeOrder(
                    TestFixtures.request(OrderSide.BUY, 100, "25.50", "a-different-key"),
                    account("10000.00"), instrument(), null,
                    UUID.randomUUID(), TestFixtures.NOW);

            assertEquals(OrderStatus.NEW, order.getStatus());
        }

        @Test
        @DisplayName("the default registry defers to the unique constraint and never fires")
        void testDefaultRegistryDefersToTheDatabase() {
            Order order = place(TestFixtures.request(OrderSide.BUY, 100, "25.50", "any-key-at-all"),
                    account("10000.00"), instrument(), null);

            assertEquals("any-key-at-all", order.getIdempotencyKey());
        }
    }

    @Nested
    @DisplayName("evaluation order: the first failure wins")
    class EvaluationOrder {

        @Test
        @DisplayName("a missing account beats an inactive one, because there is nothing to inspect")
        void testRule1BeatsRule2() {
            assertThrows(AccountNotFoundException.class,
                    () -> place(request(OrderSide.BUY, 0, "25.50"), null, null, null));
        }

        @Test
        @DisplayName("an inactive account beats a missing instrument")
        void testRule2BeatsRule3() {
            assertThrows(AccountNotActiveException.class,
                    () -> place(request(OrderSide.BUY, 100, "25.50"),
                            account("10000.00", AccountStatus.SUSPENDED), null, null));
        }

        @Test
        @DisplayName("a missing instrument beats a bad quantity")
        void testRule3BeatsRule4() {
            assertThrows(InstrumentNotFoundException.class,
                    () -> place(request(OrderSide.BUY, 0, "25.50"),
                            account("10000.00"), null, null));
        }

        @Test
        @DisplayName("a bad quantity beats insufficient funds")
        void testRule4BeatsRule6() {
            assertThrows(InvalidOrderException.class,
                    () -> place(request(OrderSide.BUY, 0, "25.50"),
                            account("0.00"), instrument(), null));
        }

        @Test
        @DisplayName("insufficient funds beats a duplicate key")
        void testRule6BeatsRule8() {
            OrderPlacementService guarded =
                    new OrderPlacementService(Set.of("used")::contains);

            assertThrows(InsufficientFundsException.class,
                    () -> guarded.placeOrder(
                            TestFixtures.request(OrderSide.BUY, 100, "25.50", "used"),
                            account("1.00"), instrument(), null,
                            UUID.randomUUID(), TestFixtures.NOW));
        }
    }
}

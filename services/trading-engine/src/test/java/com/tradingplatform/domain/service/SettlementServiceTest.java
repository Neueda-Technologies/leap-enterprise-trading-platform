package com.tradingplatform.domain.service;

import com.tradingplatform.domain.TestFixtures;
import com.tradingplatform.domain.exception.AccountNotActiveException;
import com.tradingplatform.domain.exception.InsufficientFundsException;
import com.tradingplatform.domain.exception.InsufficientHoldingsException;
import com.tradingplatform.domain.model.Account;
import com.tradingplatform.domain.model.AccountStatus;
import com.tradingplatform.domain.model.Money;
import com.tradingplatform.domain.model.Order;
import com.tradingplatform.domain.model.OrderSide;
import com.tradingplatform.domain.model.OrderStatus;
import com.tradingplatform.domain.model.Position;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static com.tradingplatform.domain.TestFixtures.ACCOUNT_ID;
import static com.tradingplatform.domain.TestFixtures.SYMBOL;
import static com.tradingplatform.domain.TestFixtures.account;
import static com.tradingplatform.domain.TestFixtures.money;
import static com.tradingplatform.domain.TestFixtures.order;
import static com.tradingplatform.domain.TestFixtures.position;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

/**
 * Business rules 9 and 10: cash and position move together, and every outcome is recorded.
 *
 * <p>The block on partial application is the one that matters. A settlement that fails must leave
 * the account, the position and the order exactly as it found them, so that the caller's rollback
 * has nothing to undo that the domain already did.
 */
@DisplayName("Settlement")
class SettlementServiceTest {

    private final SettlementService service = new SettlementService();

    @Nested
    @DisplayName("a buy")
    class Buy {

        @Test
        void testSettleBuy_DebitsCashAndIncreasesPosition() {
            Account account = account("10000.00");
            Position holding = Position.empty(ACCOUNT_ID, SYMBOL);
            Order buy = order(OrderSide.BUY, 100, "25.50");

            Settlement settlement =
                    service.settle(buy, account, holding, money("25.48"), TestFixtures.NOW);

            assertEquals(0, account.getCashBalance().compareTo(money("7452.00")));
            assertEquals(100, holding.getQuantity());
            assertEquals(0, holding.getAverageCost().compareTo(money("25.48")));
            assertEquals(OrderStatus.FILLED, buy.getStatus());
            assertEquals(0, settlement.cashDelta().compareTo(money("-2548.00")));
        }

        @Test
        @DisplayName("the cash moves at the executed price, not at the limit price")
        void testSettleBuy_UsesExecutedPrice() {
            Account account = account("10000.00");
            Order buy = order(OrderSide.BUY, 100, "25.50");

            service.settle(buy, account, null, money("20.00"), TestFixtures.NOW);

            assertEquals(0, account.getCashBalance().compareTo(money("8000.00")));
            assertEquals(0, buy.getExecutedPrice().compareTo(money("20.00")));
            assertEquals(0, buy.getPrice().compareTo(money("25.50")), "the limit price is kept");
        }

        @Test
        @DisplayName("a null position is treated as a holding of zero and is created by the fill")
        void testSettleBuy_FromNoPosition() {
            Settlement settlement = service.settle(order(OrderSide.BUY, 10, "25.50"),
                    account("10000.00"), null, money("25.50"), TestFixtures.NOW);

            assertEquals(10, settlement.positionQuantityAfter());
            assertEquals(0, settlement.averageCostAfter().compareTo(money("25.50")));
        }
    }

    @Nested
    @DisplayName("a sell")
    class Sell {

        @Test
        void testSettleSell_CreditsCashAndReducesPosition() {
            Account account = account("100.00");
            Position holding = position(100, "20.00");
            Order sell = order(OrderSide.SELL, 40, "25.50");

            Settlement settlement =
                    service.settle(sell, account, holding, money("30.00"), TestFixtures.NOW);

            assertEquals(0, account.getCashBalance().compareTo(money("1300.00")));
            assertEquals(60, holding.getQuantity());
            assertEquals(0, settlement.cashDelta().compareTo(money("1200.00")));
        }

        @Test
        @DisplayName("a sell leaves the cost basis intact so that realised P&L stays computable")
        void testSettleSell_LeavesAverageCostUnchanged() {
            Position holding = position(100, "20.00");

            Settlement settlement = service.settle(order(OrderSide.SELL, 40, "25.50"),
                    account("0.00"), holding, money("30.00"), TestFixtures.NOW);

            assertEquals(0, settlement.averageCostAfter().compareTo(money("20.00")));
        }
    }

    @Nested
    @DisplayName("nothing is applied when a precondition fails")
    class Atomicity {

        @Test
        void testSettleBuy_InsufficientFundsLeavesEverythingUnchanged() {
            Account account = account("100.00");
            Position holding = position(50, "20.00");
            Order buy = order(OrderSide.BUY, 100, "25.50");

            assertThrows(InsufficientFundsException.class,
                    () -> service.settle(buy, account, holding, money("25.50"), TestFixtures.NOW));

            assertEquals(0, account.getCashBalance().compareTo(money("100.00")));
            assertEquals(50, holding.getQuantity());
            assertEquals(OrderStatus.NEW, buy.getStatus());
            assertNull(buy.getExecutedPrice());
        }

        @Test
        void testSettleSell_InsufficientHoldingsLeavesEverythingUnchanged() {
            Account account = account("100.00");
            Position holding = position(10, "20.00");
            Order sell = order(OrderSide.SELL, 100, "25.50");

            assertThrows(InsufficientHoldingsException.class,
                    () -> service.settle(sell, account, holding, money("30.00"), TestFixtures.NOW));

            assertEquals(0, account.getCashBalance().compareTo(money("100.00")),
                    "the credit must not have been applied before the holding was checked");
            assertEquals(10, holding.getQuantity());
            assertEquals(OrderStatus.NEW, sell.getStatus());
        }

        @Test
        @DisplayName("an account suspended between placement and execution stops the fill")
        void testSettle_InactiveAccount() {
            Account account = account("10000.00", AccountStatus.SUSPENDED);
            Order buy = order(OrderSide.BUY, 10, "25.50");

            assertThrows(AccountNotActiveException.class,
                    () -> service.settle(buy, account, null, money("25.50"), TestFixtures.NOW));

            assertEquals(0, account.getCashBalance().compareTo(money("10000.00")));
            assertEquals(OrderStatus.NEW, buy.getStatus());
        }

        @Test
        void testSettle_TerminalOrderRefused() {
            Order buy = order(OrderSide.BUY, 10, "25.50");
            buy.cancel();

            assertThrows(IllegalStateException.class,
                    () -> service.settle(buy, account("10000.00"), null, money("25.50"), TestFixtures.NOW));
        }

        @Test
        void testSettle_NonPositiveExecutionPriceRefused() {
            assertThrows(IllegalArgumentException.class,
                    () -> service.settle(order(OrderSide.BUY, 10, "25.50"),
                            account("10000.00"), null, Money.ZERO, TestFixtures.NOW));
        }
    }

    @Nested
    @DisplayName("rejection and cancellation are outcomes, not failures")
    class NonFills {

        @Test
        void testReject_RecordsReasonAndMovesNoMoney() {
            Account account = account("10000.00");
            Order buy = order(OrderSide.BUY, 100, "25.50");

            Settlement settlement =
                    service.reject(buy, null, "PRICE_NOT_MET", TestFixtures.NOW);

            assertEquals(OrderStatus.REJECTED, buy.getStatus());
            assertEquals("PRICE_NOT_MET", buy.getRejectReason());
            assertEquals(0, settlement.cashDelta().compareTo(Money.ZERO));
            assertNull(settlement.executedPrice());
            assertEquals(0, account.getCashBalance().compareTo(money("10000.00")));
        }

        @Test
        void testCancel_MovesNoMoney() {
            Position holding = position(100, "20.00");
            Order buy = order(OrderSide.BUY, 100, "25.50");

            Settlement settlement = service.cancel(buy, holding, TestFixtures.NOW);

            assertEquals(OrderStatus.CANCELLED, buy.getStatus());
            assertEquals(0, settlement.cashDelta().compareTo(Money.ZERO));
            assertEquals(100, settlement.positionQuantityAfter());
        }

        @Test
        @DisplayName("a rejection reports the same shape as a fill, so one publisher covers both")
        void testReject_ReportsPositionState() {
            Settlement settlement = service.reject(order(OrderSide.SELL, 10, "25.50"),
                    position(40, "18.00"), "INSUFFICIENT_FUNDS", TestFixtures.NOW);

            assertEquals(40, settlement.positionQuantityAfter());
            assertEquals(0, settlement.averageCostAfter().compareTo(money("18.00")));
            assertEquals(OrderStatus.REJECTED, settlement.status());
        }
    }
}

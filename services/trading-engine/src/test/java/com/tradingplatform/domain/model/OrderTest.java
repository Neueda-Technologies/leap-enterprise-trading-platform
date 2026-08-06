package com.tradingplatform.domain.model;

import com.tradingplatform.domain.TestFixtures;
import com.tradingplatform.domain.exception.OrderNotCancellableException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static com.tradingplatform.domain.TestFixtures.money;
import static com.tradingplatform.domain.TestFixtures.order;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

@DisplayName("Order")
class OrderTest {

    @Nested
    @DisplayName("acceptance")
    class Acceptance {

        @Test
        @DisplayName("an accepted order starts working, with no execution price")
        void testAcceptStartsInNew() {
            Order order = order(OrderSide.BUY, 100, "25.50");

            assertEquals(OrderStatus.NEW, order.getStatus());
            assertNull(order.getExecutedPrice());
            assertNull(order.getExecutedOn());
            assertNull(order.getRejectReason());
        }

        @Test
        void testNotionalValue() {
            Order order = order(OrderSide.BUY, 100, "25.50");

            assertEquals(0, order.notionalValue().compareTo(money("2550.00")));
        }

        @Test
        @DisplayName("consideration at the executed price is not the notional at the limit price")
        void testConsiderationAtExecutedPrice() {
            Order order = order(OrderSide.BUY, 100, "25.50");

            assertEquals(0, order.considerationAt(money("25.48")).compareTo(money("2548.00")));
        }
    }

    @Nested
    @DisplayName("transitions")
    class Transitions {

        @Test
        void testFill() {
            Order order = order(OrderSide.BUY, 100, "25.50");

            order.fill(money("25.48"), TestFixtures.NOW);

            assertEquals(OrderStatus.FILLED, order.getStatus());
            assertEquals(0, order.getExecutedPrice().compareTo(money("25.48")));
            assertEquals(TestFixtures.NOW, order.getExecutedOn());
        }

        @Test
        void testReject() {
            Order order = order(OrderSide.BUY, 100, "25.50");

            order.reject("PRICE_NOT_MET", TestFixtures.NOW);

            assertEquals(OrderStatus.REJECTED, order.getStatus());
            assertEquals("PRICE_NOT_MET", order.getRejectReason());
            assertNull(order.getExecutedPrice(), "a rejected order never traded, so it has no price");
        }

        @Test
        void testCancel() {
            Order order = order(OrderSide.BUY, 100, "25.50");

            order.cancel();

            assertEquals(OrderStatus.CANCELLED, order.getStatus());
        }

        @Test
        @DisplayName("a filled order cannot be cancelled")
        void testCancel_AlreadyFilled() {
            Order order = order(OrderSide.BUY, 100, "25.50");
            order.fill(money("25.48"), TestFixtures.NOW);

            OrderNotCancellableException thrown =
                    assertThrows(OrderNotCancellableException.class, order::cancel);

            assertEquals("ORD-409", thrown.errorCode());
            assertEquals("Order is not cancellable", thrown.getMessage());
            assertEquals(OrderStatus.FILLED, thrown.status());
        }

        @Test
        void testCancel_AlreadyCancelled() {
            Order order = order(OrderSide.SELL, 10, "25.50");
            order.cancel();

            assertThrows(OrderNotCancellableException.class, order::cancel);
        }

        @Test
        @DisplayName("filling a terminal order is a programming error, not a business rule failure")
        void testFill_AlreadyTerminal() {
            Order order = order(OrderSide.BUY, 100, "25.50");
            order.cancel();

            assertThrows(IllegalStateException.class,
                    () -> order.fill(money("25.48"), TestFixtures.NOW));
        }

        @Test
        void testIsCancellable() {
            Order working = order(OrderSide.BUY, 100, "25.50");
            assertTrue(working.isCancellable());

            working.fill(money("25.48"), TestFixtures.NOW);
            assertFalse(working.isCancellable());
        }
    }

    @Nested
    @DisplayName("status")
    class Status {

        @Test
        void testTerminalStates() {
            assertFalse(OrderStatus.NEW.isTerminal());
            assertTrue(OrderStatus.FILLED.isTerminal());
            assertTrue(OrderStatus.REJECTED.isTerminal());
            assertTrue(OrderStatus.CANCELLED.isTerminal());
        }
    }
}

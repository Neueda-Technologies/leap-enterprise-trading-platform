package com.tradingplatform.domain.model;

import com.tradingplatform.domain.exception.InsufficientHoldingsException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static com.tradingplatform.domain.TestFixtures.ACCOUNT_ID;
import static com.tradingplatform.domain.TestFixtures.SYMBOL;
import static com.tradingplatform.domain.TestFixtures.money;
import static com.tradingplatform.domain.TestFixtures.position;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

@DisplayName("Position")
class PositionTest {

    @Nested
    @DisplayName("apply a buy")
    class Buy {

        @Test
        @DisplayName("a first buy sets the quantity and the average cost to the fill price")
        void testBuy_FromEmpty() {
            Position position = Position.empty(ACCOUNT_ID, SYMBOL);

            position.apply(OrderSide.BUY, 100, money("25.50"));

            assertEquals(100, position.getQuantity());
            assertEquals(0, position.getAverageCost().compareTo(money("25.50")));
        }

        @Test
        @DisplayName("a second buy recalculates the weighted average cost")
        void testBuy_RecalculatesAverageCost() {
            Position position = position(100, "20.00");

            position.apply(OrderSide.BUY, 100, money("30.00"));

            assertEquals(200, position.getQuantity());
            assertEquals(0, position.getAverageCost().compareTo(money("25.00")));
        }

        @Test
        @DisplayName("the weighted average is weighted, not a plain mean")
        void testBuy_WeightsByQuantity() {
            Position position = position(300, "10.00");

            position.apply(OrderSide.BUY, 100, money("50.00"));

            // (300 * 10.00 + 100 * 50.00) / 400 = 8000 / 400 = 20.00
            assertEquals(400, position.getQuantity());
            assertEquals(0, position.getAverageCost().compareTo(money("20.00")));
        }

        @Test
        @DisplayName("an average cost that does not divide exactly is rounded once, to two places")
        void testBuy_RoundsAverageCostToTwoPlaces() {
            Position position = position(1, "10.00");

            position.apply(OrderSide.BUY, 2, money("10.01"));

            // (1 * 10.00 + 2 * 10.01) / 3 = 30.02 / 3 = 10.006666..., rounded to 10.01
            assertEquals(3, position.getQuantity());
            assertEquals(0, position.getAverageCost().compareTo(money("10.01")));
            assertEquals(2, position.getAverageCost().scale());
        }
    }

    @Nested
    @DisplayName("apply a sell")
    class Sell {

        @Test
        void testSell_ReducesQuantity() {
            Position position = position(100, "25.50");

            position.apply(OrderSide.SELL, 40, money("30.00"));

            assertEquals(60, position.getQuantity());
        }

        @Test
        @DisplayName("a sell leaves the cost basis alone, which is what makes realised P&L computable")
        void testSell_LeavesAverageCostUnchanged() {
            Position position = position(100, "25.50");

            position.apply(OrderSide.SELL, 40, money("30.00"));

            assertEquals(0, position.getAverageCost().compareTo(money("25.50")));
        }

        @Test
        @DisplayName("selling the whole holding empties it without going negative")
        void testSell_EntireHolding() {
            Position position = position(100, "25.50");

            position.apply(OrderSide.SELL, 100, money("30.00"));

            assertEquals(0, position.getQuantity());
            assertTrue(position.isEmpty());
        }

        @Test
        @DisplayName("business rule 7: a sell larger than the holding is refused")
        void testSell_InsufficientHoldings() {
            Position position = position(50, "25.50");

            InsufficientHoldingsException thrown = assertThrows(InsufficientHoldingsException.class,
                    () -> position.apply(OrderSide.SELL, 51, money("30.00")));

            assertEquals("ORD-409", thrown.errorCode());
            assertEquals("Insufficient holdings", thrown.getMessage());
            assertEquals(51, thrown.requested());
            assertEquals(50, thrown.held());
        }

        @Test
        @DisplayName("a refused sell leaves the position exactly as it was")
        void testSell_InsufficientHoldingsLeavesPositionUnchanged() {
            Position position = position(50, "25.50");

            assertThrows(InsufficientHoldingsException.class,
                    () -> position.apply(OrderSide.SELL, 500, money("30.00")));

            assertEquals(50, position.getQuantity());
            assertEquals(0, position.getAverageCost().compareTo(money("25.50")));
        }

        @Test
        void testSell_FromEmptyPosition() {
            Position position = Position.empty(ACCOUNT_ID, SYMBOL);

            assertThrows(InsufficientHoldingsException.class,
                    () -> position.apply(OrderSide.SELL, 1, money("30.00")));
        }
    }

    @Nested
    @DisplayName("valuation")
    class Valuation {

        @Test
        void testMarketValue_QuantityTimesPrice() {
            Position position = position(100, "25.50");

            assertEquals(0, position.marketValue(money("30.00")).compareTo(money("3000.00")));
        }

        @Test
        void testMarketValue_EmptyPositionIsWorthNothing() {
            Position position = Position.empty(ACCOUNT_ID, SYMBOL);

            assertEquals(0, position.marketValue(money("30.00")).compareTo(Money.ZERO));
        }

        @Test
        @DisplayName("market value less cost basis is the unrealised profit and loss")
        void testCostBasis() {
            Position position = position(100, "25.50");

            assertEquals(0, position.costBasis().compareTo(money("2550.00")));
            assertEquals(0, position.marketValue(money("30.00"))
                    .subtract(position.costBasis()).compareTo(money("450.00")));
        }

        @Test
        void testMarketValue_RequiresAPrice() {
            Position position = position(100, "25.50");

            assertThrows(NullPointerException.class, () -> position.marketValue(null));
        }
    }

    @Nested
    @DisplayName("guards")
    class Guards {

        @Test
        void testCanCover() {
            Position position = position(100, "25.50");

            assertTrue(position.canCover(99));
            assertTrue(position.canCover(100));
            assertFalse(position.canCover(101));
        }

        @Test
        void testApply_ZeroQuantityRejected() {
            Position position = position(100, "25.50");

            assertThrows(IllegalArgumentException.class,
                    () -> position.apply(OrderSide.BUY, 0, money("25.50")));
        }

        @Test
        void testConstructor_NegativeQuantityRejected() {
            assertThrows(IllegalArgumentException.class,
                    () -> new Position(ACCOUNT_ID, SYMBOL, -1, money("25.50")));
        }
    }
}

package com.neueda.trading.executor.execution;

import static org.assertj.core.api.Assertions.assertThat;

import com.neueda.trading.executor.domain.Side;
import java.math.BigDecimal;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

/**
 * The fill rules are pure functions, so they are tested without a database, a broker or a clock.
 * Anything that needs one of those is not a pricing rule and does not belong in this class.
 */
class FillPolicyTest {

    private static BigDecimal money(String value) {
        return new BigDecimal(value);
    }

    @Nested
    @DisplayName("marketability")
    class Marketability {

        @Test
        void buyIsMarketableWhenTheQuoteIsAtOrBelowTheLimit() {
            assertThat(FillPolicy.isMarketable(Side.BUY, money("233.00"), money("232.71"))).isTrue();
            assertThat(FillPolicy.isMarketable(Side.BUY, money("233.00"), money("233.00"))).isTrue();
            assertThat(FillPolicy.isMarketable(Side.BUY, money("233.00"), money("233.01"))).isFalse();
        }

        @Test
        void sellIsMarketableWhenTheQuoteIsAtOrAboveTheLimit() {
            assertThat(FillPolicy.isMarketable(Side.SELL, money("230.00"), money("232.71"))).isTrue();
            assertThat(FillPolicy.isMarketable(Side.SELL, money("230.00"), money("230.00"))).isTrue();
            assertThat(FillPolicy.isMarketable(Side.SELL, money("230.00"), money("229.99"))).isFalse();
        }

        @Test
        void theQuoteIsRoundedBeforeItIsComparedWithTheLimit() {
            // 233.004 rounds to 233.00 and is inside a 233.00 limit.
            assertThat(FillPolicy.isMarketable(Side.BUY, money("233.00"), money("233.004"))).isTrue();
            // 233.006 rounds to 233.01 and is outside it.
            assertThat(FillPolicy.isMarketable(Side.BUY, money("233.00"), money("233.006"))).isFalse();
        }
    }

    @Nested
    @DisplayName("fill price")
    class FillPrice {

        @Test
        void buyFillsAtTheLowerOfTheLimitAndTheQuote() {
            assertThat(FillPolicy.fillPrice(Side.BUY, money("233.00"), money("232.71")))
                    .isEqualByComparingTo("232.71");
            assertThat(FillPolicy.fillPrice(Side.BUY, money("233.00"), money("240.00")))
                    .isEqualByComparingTo("233.00");
        }

        @Test
        void sellFillsAtTheHigherOfTheLimitAndTheQuote() {
            assertThat(FillPolicy.fillPrice(Side.SELL, money("230.00"), money("232.71")))
                    .isEqualByComparingTo("232.71");
            assertThat(FillPolicy.fillPrice(Side.SELL, money("230.00"), money("220.00")))
                    .isEqualByComparingTo("230.00");
        }

        @Test
        void aMarketableOrderAlwaysFillsAtTheQuote() {
            assertThat(FillPolicy.fillPrice(Side.BUY, money("233.00"), money("232.7149")))
                    .isEqualByComparingTo("232.71");
            assertThat(FillPolicy.fillPrice(Side.SELL, money("230.00"), money("232.7149")))
                    .isEqualByComparingTo("232.71");
        }

        @Test
        void theFillPriceIsAlwaysAtTheMoneyScale() {
            assertThat(FillPolicy.fillPrice(Side.BUY, money("233.00"), money("232.7149")).scale())
                    .isEqualTo(2);
        }
    }

    @Nested
    @DisplayName("arithmetic")
    class Arithmetic {

        @Test
        void notionalIsQuantityMultipliedByPrice() {
            assertThat(FillPolicy.notional(100, money("232.71"))).isEqualByComparingTo("23271.00");
        }

        @Test
        void averageCostAfterABuyIsTheWeightedAverage() {
            // 200 held at 228.00, buying 100 at 232.71.
            assertThat(FillPolicy.averageCostAfterBuy(200, money("228.00"), 100, money("232.71")))
                    .isEqualByComparingTo("229.57");
        }

        @Test
        void theFirstBuyAveragesToTheFillPrice() {
            assertThat(FillPolicy.averageCostAfterBuy(0, BigDecimal.ZERO, 40, money("1580.25")))
                    .isEqualByComparingTo("1580.25");
        }

        @Test
        void averageCostIsRoundedToTheMoneyScale() {
            // (1 * 10.00 + 2 * 10.01) / 3 = 10.006666..., which the money scale rounds to 10.01.
            assertThat(FillPolicy.averageCostAfterBuy(1, money("10.00"), 2, money("10.01")))
                    .isEqualByComparingTo("10.01");
        }
    }
}

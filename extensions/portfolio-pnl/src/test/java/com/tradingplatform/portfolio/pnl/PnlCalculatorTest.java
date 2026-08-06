package com.tradingplatform.portfolio.pnl;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

/**
 * Verifies the arithmetic in the "Definitions" section of docs/contracts/portfolio-api.yaml:
 * weighted average cost, cost basis, market value, unrealised profit and loss, and
 * realised profit and loss on a sale, including a partial sell.
 */
class PnlCalculatorTest {

    @Nested
    class WeightedAverageCost {

        @Test
        void firstBuyEstablishesAverageCostAtTheFillPrice() {
            BigDecimal average = PnlCalculator.weightedAverageCostAfterBuy(0, BigDecimal.ZERO, 100, new BigDecimal("228.40"));

            assertThat(average).isEqualByComparingTo("228.40");
        }

        @Test
        void secondBuyAtAHigherPriceRaisesTheAverage() {
            // Example from portfolio-api.yaml: (oldQty*oldAvg + newQty*fillPrice) / (oldQty+newQty)
            // 200 @ 228.40 then 100 @ 240.00 => (200*228.40 + 100*240.00) / 300 = 232.2666..
            BigDecimal average =
                    PnlCalculator.weightedAverageCostAfterBuy(200, new BigDecimal("228.40"), 100, new BigDecimal("240.00"));

            assertThat(average).isEqualByComparingTo("232.27");
        }

        @Test
        void secondBuyAtALowerPriceLowersTheAverage() {
            BigDecimal average =
                    PnlCalculator.weightedAverageCostAfterBuy(100, new BigDecimal("100.00"), 100, new BigDecimal("80.00"));

            assertThat(average).isEqualByComparingTo("90.00");
        }

        @Test
        void rejectsAZeroOrNegativeResultingQuantity() {
            assertThat(
                    org.junit.jupiter.api.Assertions.assertThrows(
                            IllegalArgumentException.class,
                            () -> PnlCalculator.weightedAverageCostAfterBuy(0, BigDecimal.ZERO, 0, BigDecimal.TEN)))
                    .hasMessageContaining("positive");
        }
    }

    @Nested
    class CostBasisAndMarketValue {

        @Test
        void costBasisIsQuantityTimesAverageCost() {
            assertThat(PnlCalculator.costBasis(200, new BigDecimal("228.40"))).isEqualByComparingTo("45680.00");
        }

        @Test
        void marketValueIsQuantityTimesLastPrice() {
            assertThat(PnlCalculator.marketValue(200, new BigDecimal("232.71"))).isEqualByComparingTo("46542.00");
        }

        @Test
        void unrealisedPnlIsMarketValueMinusCostBasis() {
            BigDecimal marketValue = new BigDecimal("46542.00");
            BigDecimal costBasis = new BigDecimal("45680.00");

            assertThat(PnlCalculator.unrealisedPnl(marketValue, costBasis)).isEqualByComparingTo("862.00");
        }

        @Test
        void unrealisedPnlMovesNegativeWhenTheQuoteFallsBelowCost() {
            BigDecimal marketValue = new BigDecimal("40000.00");
            BigDecimal costBasis = new BigDecimal("45680.00");

            assertThat(PnlCalculator.unrealisedPnl(marketValue, costBasis)).isEqualByComparingTo("-5680.00");
        }

        @Test
        void unrealisedPnlPercentIsExpressedInPercentagePoints() {
            // 862.00 / 45680.00 * 100 = 1.8871...
            BigDecimal percent = PnlCalculator.unrealisedPnlPercent(new BigDecimal("862.00"), new BigDecimal("45680.00"));

            assertThat(percent).isEqualByComparingTo("1.89");
        }

        @Test
        void unrealisedPnlPercentIsNullWhenCostBasisIsZero() {
            assertThat(PnlCalculator.unrealisedPnlPercent(BigDecimal.ZERO, BigDecimal.ZERO)).isNull();
        }
    }

    @Nested
    class RealisedPnlOnSale {

        @Test
        void bookedAsFillPriceMinusAverageCostAtSaleTimesQuantitySold() {
            BigDecimal realised = PnlCalculator.realisedPnlOnSale(new BigDecimal("250.00"), new BigDecimal("228.40"), 100);

            // (250.00 - 228.40) * 100 = 2160.00
            assertThat(realised).isEqualByComparingTo("2160.00");
        }

        @Test
        void partialSellBooksOnlyTheSoldQuantity() {
            // Holding 200 @ 228.40 average cost, sell 60 at 250.00. Average cost of the
            // remaining 140 shares is untouched; only the 60 sold are booked.
            BigDecimal realised = PnlCalculator.realisedPnlOnSale(new BigDecimal("250.00"), new BigDecimal("228.40"), 60);

            assertThat(realised).isEqualByComparingTo("1296.00");
        }

        @Test
        void aLossOnSaleIsNegative() {
            BigDecimal realised = PnlCalculator.realisedPnlOnSale(new BigDecimal("200.00"), new BigDecimal("228.40"), 100);

            assertThat(realised).isEqualByComparingTo("-2840.00");
        }

        @Test
        void realisedPnlIgnoresAnyCurrentPriceArgumentBecauseThereIsNoSuchArgument() {
            // The method signature itself is the guard against the "common error" the
            // contract calls out: computing realised profit and loss from today's
            // price. There is no current-price parameter to pass by mistake.
            assertThat(PnlCalculator.class.getDeclaredMethods())
                    .filteredOn(m -> m.getName().equals("realisedPnlOnSale"))
                    .hasSize(1)
                    .allSatisfy(m -> assertThat(m.getParameterCount()).isEqualTo(3));
        }
    }

    @Nested
    class TotalValue {

        @Test
        void totalValueIsCashPlusMarketValue() {
            BigDecimal total = PnlCalculator.totalValue(new BigDecimal("24500.75"), new BigDecimal("65120.00"));

            assertThat(total).isEqualByComparingTo("89620.75");
        }
    }
}

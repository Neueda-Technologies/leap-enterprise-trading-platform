package com.tradingplatform.portfolio.pnl;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * The profit-and-loss arithmetic, in one place, matching the "Definitions" section of
 * docs/contracts/portfolio-api.yaml word for word. No framework dependency and no I/O,
 * on the same principle as the Sprint 5 domain engine: the arithmetic is worth getting
 * right in isolation, before anything calls it over HTTP or off a Kafka topic.
 *
 * <p>All money arithmetic uses {@link BigDecimal} at two decimal places with
 * {@link RoundingMode#HALF_UP}, matching the {@code NUMERIC(18,2)} convention in
 * database-schema.sql. A binary floating-point balance cannot represent 0.10 exactly
 * and drifts over many trades; the same argument applies to profit and loss, which is
 * accumulated over the lifetime of an account.
 */
public final class PnlCalculator {

    private static final int SCALE = 2;
    private static final int PERCENT_SCALE = 2;

    private PnlCalculator() {
    }

    /**
     * Weighted average cost after a buy: {@code (oldQty * oldAvg + newQty * fillPrice) / (oldQty + newQty)}.
     * A sell never calls this: average cost is unchanged by a sell, which is what makes
     * realised profit and loss computable at the point of sale.
     *
     * @throws IllegalArgumentException if the resulting quantity is zero or negative
     */
    public static BigDecimal weightedAverageCostAfterBuy(
            int oldQuantity, BigDecimal oldAverageCost, int newQuantity, BigDecimal fillPrice) {
        int totalQuantity = oldQuantity + newQuantity;
        if (totalQuantity <= 0) {
            throw new IllegalArgumentException("Total quantity after a buy must be positive");
        }
        BigDecimal oldCost = oldAverageCost.multiply(BigDecimal.valueOf(oldQuantity));
        BigDecimal newCost = fillPrice.multiply(BigDecimal.valueOf(newQuantity));
        return oldCost.add(newCost).divide(BigDecimal.valueOf(totalQuantity), SCALE, RoundingMode.HALF_UP);
    }

    /** Cost basis for a position: {@code quantity * averageCost}. */
    public static BigDecimal costBasis(int quantity, BigDecimal averageCost) {
        return averageCost.multiply(BigDecimal.valueOf(quantity)).setScale(SCALE, RoundingMode.HALF_UP);
    }

    /** Market value for a position: {@code quantity * lastPrice}. */
    public static BigDecimal marketValue(int quantity, BigDecimal lastPrice) {
        return lastPrice.multiply(BigDecimal.valueOf(quantity)).setScale(SCALE, RoundingMode.HALF_UP);
    }

    /** Unrealised profit and loss: {@code marketValue - costBasis}. Never persisted; recomputed on every call. */
    public static BigDecimal unrealisedPnl(BigDecimal marketValue, BigDecimal costBasis) {
        return marketValue.subtract(costBasis).setScale(SCALE, RoundingMode.HALF_UP);
    }

    /**
     * Unrealised profit and loss as a percentage of cost basis, in percentage points
     * ({@code 6.23} means 6.23 per cent). Null when cost basis is zero, since the
     * percentage is undefined, not infinite.
     */
    public static BigDecimal unrealisedPnlPercent(BigDecimal unrealisedPnl, BigDecimal costBasis) {
        if (costBasis == null || costBasis.compareTo(BigDecimal.ZERO) == 0) {
            return null;
        }
        return unrealisedPnl
                .divide(costBasis, 6, RoundingMode.HALF_UP)
                .multiply(BigDecimal.valueOf(100))
                .setScale(PERCENT_SCALE, RoundingMode.HALF_UP);
    }

    /**
     * Realised profit and loss booked at a sell: {@code (fillPrice - averageCostAtSale) * quantitySold}.
     * Booked once, at the moment of sale, and never recomputed from a later price. A
     * common error is to compute realised profit and loss from today's price; this
     * method deliberately takes no current price, so that mistake cannot compile.
     */
    public static BigDecimal realisedPnlOnSale(BigDecimal fillPrice, BigDecimal averageCostAtSale, int quantitySold) {
        return fillPrice
                .subtract(averageCostAtSale)
                .multiply(BigDecimal.valueOf(quantitySold))
                .setScale(SCALE, RoundingMode.HALF_UP);
    }

    /** Total portfolio value: {@code cashBalance + sum(marketValue)}. */
    public static BigDecimal totalValue(BigDecimal cashBalance, BigDecimal totalMarketValue) {
        return cashBalance.add(totalMarketValue).setScale(SCALE, RoundingMode.HALF_UP);
    }
}

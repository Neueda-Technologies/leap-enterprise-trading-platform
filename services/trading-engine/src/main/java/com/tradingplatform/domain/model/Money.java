package com.tradingplatform.domain.model;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * Arithmetic helpers for money.
 *
 * <p>Money in this platform is {@link BigDecimal} at scale 2, matching {@code NUMERIC(18,2)} in the
 * operational schema. Never {@code double}, never {@code float}. Binary floating point cannot
 * represent 0.10 exactly, and a cash balance built from a few thousand additions of values it cannot
 * represent drifts away from the truth. A trading system whose balance is approximately right is a
 * trading system that is wrong.
 *
 * <p>Rounding is {@code HALF_UP}, applied at one point only: the end of a calculation. Rounding
 * intermediate results compounds the error.
 */
public final class Money {

    /** Decimal places held for every monetary value, matching {@code NUMERIC(18,2)}. */
    public static final int SCALE = 2;

    /** Rounding applied when a calculation produces more than {@link #SCALE} decimal places. */
    public static final RoundingMode ROUNDING = RoundingMode.HALF_UP;

    /** Zero, already at the platform scale. */
    public static final BigDecimal ZERO = BigDecimal.ZERO.setScale(SCALE);

    private Money() {
        // Utility class.
    }

    /**
     * Reads a decimal literal as money. Use it in tests and fixtures rather than
     * {@code BigDecimal.valueOf(double)}, which reintroduces the floating-point error this class
     * exists to avoid.
     */
    public static BigDecimal of(String value) {
        return normalise(new BigDecimal(value));
    }

    /** Brings a value to the platform scale. */
    public static BigDecimal normalise(BigDecimal value) {
        return value.setScale(SCALE, ROUNDING);
    }

    /**
     * Consideration for a quantity at a unit price: {@code quantity * price}, rounded once at the
     * end.
     */
    public static BigDecimal consideration(int quantity, BigDecimal price) {
        return normalise(price.multiply(BigDecimal.valueOf(quantity)));
    }

    /** True when the value is greater than zero. */
    public static boolean isPositive(BigDecimal value) {
        return value != null && value.signum() > 0;
    }

    /**
     * Compares two monetary values by numeric value, ignoring scale. {@code BigDecimal.equals}
     * treats 25.5 and 25.50 as different objects, which is almost never what a money comparison
     * means.
     */
    public static boolean equal(BigDecimal left, BigDecimal right) {
        return left.compareTo(right) == 0;
    }
}

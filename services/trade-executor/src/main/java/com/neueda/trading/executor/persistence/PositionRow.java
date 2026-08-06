package com.neueda.trading.executor.persistence;

import java.math.BigDecimal;

/**
 * A row of {@code positions}. An account that has never held the instrument has no row, which is
 * represented as a flat position rather than as null, so the fill arithmetic has one code path.
 */
public record PositionRow(long accountId, String symbol, int quantity, BigDecimal averageCost) {

    public static PositionRow empty(long accountId, String symbol) {
        return new PositionRow(accountId, symbol, 0, BigDecimal.ZERO);
    }
}

package com.neueda.trading.executor.persistence;

import java.math.BigDecimal;

/**
 * The columns of {@code accounts} the executor reads.
 *
 * @param version the optimistic lock value read at the start of the transaction. Every cash write
 *                carries it in the WHERE clause, so a concurrent writer costs a retry rather than a
 *                lost update.
 */
public record AccountRow(long id, BigDecimal cashBalance, String status, int version) {

    public boolean isActive() {
        return "ACTIVE".equals(status);
    }
}

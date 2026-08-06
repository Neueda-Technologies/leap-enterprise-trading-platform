package com.neueda.trading.executor.domain;

/**
 * Order lifecycle states. {@code NEW} is the only working state; the other three are terminal.
 * There is no partial-fill state, so the executor fills in full or rejects.
 */
public enum OrderStatus {
    NEW,
    FILLED,
    REJECTED,
    CANCELLED
}

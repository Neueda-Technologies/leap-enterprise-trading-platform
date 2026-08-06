package com.tradingplatform.domain.model;

/**
 * Direction of an order.
 *
 * <p>There are exactly two. Short selling is out of scope, so a {@code SELL} can never take a
 * position below zero and the platform never holds a negative quantity.
 */
public enum OrderSide {

    /** Acquire the instrument. Spends cash, increases the position. */
    BUY,

    /** Dispose of the instrument. Releases cash, decreases the position. */
    SELL
}

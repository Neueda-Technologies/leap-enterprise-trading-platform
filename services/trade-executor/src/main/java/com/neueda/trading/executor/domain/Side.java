package com.neueda.trading.executor.domain;

/** Direction of an order. Matches {@code orders.side} and the Kafka payload enum. */
public enum Side {
    BUY,
    SELL
}

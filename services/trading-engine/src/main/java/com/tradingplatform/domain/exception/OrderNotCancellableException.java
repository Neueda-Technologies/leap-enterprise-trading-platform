package com.tradingplatform.domain.exception;

import com.tradingplatform.domain.model.OrderStatus;

import java.util.UUID;

/**
 * The order is already {@code FILLED}, {@code REJECTED} or {@code CANCELLED}, so it cannot be
 * cancelled.
 *
 * <p>Catalogue code {@code ORD-409}, mapped to HTTP 409 by the Trade REST API.
 *
 * <p>The check that raises this must be a guarded transition, not a read followed by a write. The
 * Trade REST API cancels with {@code UPDATE orders SET status = 'CANCELLED' WHERE id = ? AND
 * status = 'NEW'} and treats zero rows affected as this failure. Reading the status first and then
 * updating races the Trade Executor, which is filling the same row from another process.
 *
 * <p>Not one of the six exceptions named in the Sprint 5 specification. See the README.
 */
public class OrderNotCancellableException extends TradingException {

    /** Catalogue code raised by this exception. */
    public static final String ERROR_CODE = "ORD-409";

    private final transient UUID orderId;
    private final transient OrderStatus status;

    public OrderNotCancellableException(UUID orderId, OrderStatus status) {
        super(ERROR_CODE, "Order is not cancellable");
        this.orderId = orderId;
        this.status = status;
    }

    /** The order that was addressed. For logging, never for the response body. */
    public UUID orderId() {
        return orderId;
    }

    /**
     * The status observed when the transition was refused. May be null when the guarded update
     * reported zero rows affected without re-reading the row.
     */
    public OrderStatus status() {
        return status;
    }
}

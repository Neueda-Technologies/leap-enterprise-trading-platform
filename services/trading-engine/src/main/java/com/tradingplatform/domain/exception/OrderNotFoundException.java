package com.tradingplatform.domain.exception;

import java.util.UUID;

/**
 * No order exists with the requested identifier.
 *
 * <p>Catalogue code {@code ORD-409}, mapped to HTTP 404 by the Trade REST API. The pairing looks
 * wrong and is deliberate: {@code contracts/trade-api.yaml} defines the 404 response of
 * {@code DELETE /api/v1/orders/{id}} with {@code errorCode: ORD-409}, and the catalogue is a closed
 * enumeration with no order-not-found code. The contract wins. This is the reason the contract tells
 * clients to branch on {@code errorCode} together with the status, never on either alone.
 *
 * <p>Not one of the six exceptions named in the Sprint 5 specification. See the README.
 */
public class OrderNotFoundException extends TradingException {

    /** Catalogue code raised by this exception. */
    public static final String ERROR_CODE = "ORD-409";

    private final transient UUID orderId;

    public OrderNotFoundException(UUID orderId) {
        super(ERROR_CODE, "Order not found");
        this.orderId = orderId;
    }

    /** The identifier that was looked up. For logging, never for the response body. */
    public UUID orderId() {
        return orderId;
    }
}

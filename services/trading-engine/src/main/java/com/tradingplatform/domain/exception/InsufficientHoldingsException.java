package com.tradingplatform.domain.exception;

/**
 * Business rule 7. A sell is larger than the quantity held.
 *
 * <p>Catalogue code {@code ORD-409}, mapped to HTTP 409 by the Trade REST API. It is a conflict
 * rather than a bad request because the request is well formed and would have been accepted against
 * a different holding.
 *
 * <p>Short selling is out of scope, so there is no configuration under which this rule is relaxed.
 */
public class InsufficientHoldingsException extends TradingException {

    /** Catalogue code raised by this exception. */
    public static final String ERROR_CODE = "ORD-409";

    private final transient String symbol;
    private final transient int requested;
    private final transient int held;

    public InsufficientHoldingsException(String symbol, int requested, int held) {
        super(ERROR_CODE, "Insufficient holdings");
        this.symbol = symbol;
        this.requested = requested;
        this.held = held;
    }

    /** The instrument the sell was for. For logging, never for the response body. */
    public String symbol() {
        return symbol;
    }

    /** Quantity the order asked to sell. For logging. */
    public int requested() {
        return requested;
    }

    /** Quantity the account actually held. For logging. */
    public int held() {
        return held;
    }
}

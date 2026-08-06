package com.tradingplatform.domain.exception;

import java.math.BigDecimal;

/**
 * Business rule 6. A buy costs more than the available cash balance.
 *
 * <p>Catalogue code {@code ORD-400}, mapped to HTTP 400 by the Trade REST API.
 *
 * <p>The check is a comparison, not a subtraction that is later inspected for a negative result. The
 * non-negative check constraint on {@code accounts.cash_balance} is a last line of defence: if it
 * ever fires, this rule was skipped.
 */
public class InsufficientFundsException extends TradingException {

    /** Catalogue code raised by this exception. */
    public static final String ERROR_CODE = "ORD-400";

    private final transient BigDecimal required;
    private final transient BigDecimal available;

    public InsufficientFundsException(BigDecimal required, BigDecimal available) {
        super(ERROR_CODE, "Insufficient funds");
        this.required = required;
        this.available = available;
    }

    /** Cash the order would have consumed. For logging, never for the response body. */
    public BigDecimal required() {
        return required;
    }

    /** Cash the account held. For logging, never for the response body. */
    public BigDecimal available() {
        return available;
    }
}

package com.tradingplatform.domain.exception;

/**
 * Business rules 4 and 5. Quantity is not greater than zero, or price is not greater than zero.
 *
 * <p>Catalogue code {@code VAL-422}, mapped to HTTP 422 by the Trade REST API.
 *
 * <p>This exception is not one of the six named in the Sprint 5 specification. It exists because
 * rules 4 and 5 are business rules with an error code, and the specification's list of exceptions
 * has no member for them. The alternative, relying only on Bean Validation, would leave the two
 * rules unenforceable by any caller of this library that is not a Spring controller. See the README
 * for the full list of additions.
 */
public class InvalidOrderException extends TradingException {

    /** Catalogue code raised by this exception. */
    public static final String ERROR_CODE = "VAL-422";

    private final transient String field;
    private final transient String detail;

    public InvalidOrderException(String field, String detail) {
        super(ERROR_CODE, "Invalid input");
        this.field = field;
        this.detail = detail;
    }

    /** The offending field, for example {@code quantity}. For logging, never for the response body. */
    public String field() {
        return field;
    }

    /** Why the field was refused. For logging, never for the response body. */
    public String detail() {
        return detail;
    }
}

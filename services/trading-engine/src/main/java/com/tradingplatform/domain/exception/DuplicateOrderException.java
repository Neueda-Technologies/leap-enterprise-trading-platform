package com.tradingplatform.domain.exception;

/**
 * Business rule 8. The idempotency key has already been accepted.
 *
 * <p>Catalogue code {@code ORD-409}, mapped to HTTP 409 by the Trade REST API.
 *
 * <p>In the Trade REST API this exception is raised from a unique constraint violation on
 * {@code orders.idempotency_key}, not from a select followed by an insert. A read-then-write check
 * has a race that two concurrent requests will find, and the side effect of losing that race is a
 * duplicated trade. The domain keeps an {@link com.tradingplatform.domain.service.IdempotencyKeyRegistry}
 * seam so that the rule can be stated and tested without a database, but the database is the
 * authority.
 *
 * <p>Retrying with the same key is not a way to poll for status. It returns this error. Poll
 * {@code GET /api/v1/accounts/{id}/orders} instead.
 */
public class DuplicateOrderException extends TradingException {

    /** Catalogue code raised by this exception. */
    public static final String ERROR_CODE = "ORD-409";

    private final transient String idempotencyKey;

    public DuplicateOrderException(String idempotencyKey) {
        super(ERROR_CODE, "Duplicate order");
        this.idempotencyKey = idempotencyKey;
    }

    /** The key that had already been used. For logging, never for the response body. */
    public String idempotencyKey() {
        return idempotencyKey;
    }
}

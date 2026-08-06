package com.tradingplatform.domain.service;

/**
 * Answers whether an idempotency key has already been accepted.
 *
 * <p>Read the warning before implementing this. In the Trade REST API the authority for business
 * rule 8 is the unique constraint on {@code orders.idempotency_key}. The insert is attempted, and a
 * constraint violation is translated into
 * {@link com.tradingplatform.domain.exception.DuplicateOrderException}. Implementing this interface
 * as a {@code SELECT} that the service runs before the {@code INSERT} recreates exactly the race the
 * constraint exists to close: two concurrent requests carrying the same key both find no row, both
 * pass, and both insert.
 *
 * <p>The seam exists so that rule 8 can be stated in the domain and tested without a database. The
 * default implementation, {@link #none()}, answers false for every key and defers to the database.
 * A test implementation backed by a set is the intended second use.
 */
@FunctionalInterface
public interface IdempotencyKeyRegistry {

    /** True when an order has already been accepted with this key. */
    boolean isKnown(String idempotencyKey);

    /**
     * A registry that knows nothing. Use it when persistence enforces the rule, which is every case
     * outside a test.
     */
    static IdempotencyKeyRegistry none() {
        return key -> false;
    }
}

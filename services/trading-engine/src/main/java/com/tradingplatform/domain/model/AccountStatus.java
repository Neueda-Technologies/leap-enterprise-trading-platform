package com.tradingplatform.domain.model;

/**
 * Lifecycle state of a trading account.
 *
 * <p>Only {@link #ACTIVE} may place or cancel orders. {@code SUSPENDED} is reversible, {@code CLOSED}
 * is not. Both are refused with the same error, {@code ACC-403}, because telling a caller which of
 * the two applies leaks account state to someone who has not been shown to own the account.
 *
 * <p>Stored as {@code VARCHAR} with a check constraint rather than a Postgres enum type, so MyBatis
 * maps it without a type handler.
 */
public enum AccountStatus {

    /** Trading is permitted. */
    ACTIVE,

    /** Trading is blocked, reversibly. The account and its holdings remain. */
    SUSPENDED,

    /** Trading is blocked permanently. History is retained because it is the audit trail. */
    CLOSED
}

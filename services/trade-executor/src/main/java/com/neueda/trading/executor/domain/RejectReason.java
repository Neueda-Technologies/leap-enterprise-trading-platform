package com.neueda.trading.executor.domain;

/**
 * Machine-readable rejection causes. The value is written to {@code orders.reject_reason} and
 * copied onto the {@code trade-events} payload as {@code reason}, so the two always agree.
 *
 * <p>The topic contract gives {@code INSUFFICIENT_FUNDS}, {@code PRICE_NOT_MET},
 * {@code INSTRUMENT_NOT_TRADABLE} and {@code CANCELLED_BY_CUSTOMER} as examples and leaves the set
 * open. Three values are added here, each for a state that only exists once execution is
 * asynchronous: the price feed can be down, the account can be suspended after the order was
 * accepted, and the holding can be sold by another order first.
 *
 * <p>{@code CANCELLED_BY_CUSTOMER} is not in this enum. Cancellation is the Trade REST API's
 * transition, not the executor's.
 *
 * <p>Every value fits {@code VARCHAR(64)}.
 */
public enum RejectReason {

    /**
     * Fauxnance returned nothing usable for the symbol after the retry budget was spent. This is
     * the executor's analogue of {@code MKT-503} in the platform error catalogue: pricing
     * unavailable. An order that cannot be priced cannot be filled, and leaving it NEW for ever is
     * worse for the customer than rejecting it.
     */
    PRICING_UNAVAILABLE,

    /** The quote is outside the order's limit price. */
    PRICE_NOT_MET,

    /** The instrument was suspended between acceptance and execution. */
    INSTRUMENT_NOT_TRADABLE,

    /** Cash at execution time does not cover the fill. Rule 6, re-checked at the fill price. */
    INSUFFICIENT_FUNDS,

    /** Held quantity at execution time does not cover the sell. Rule 7, re-checked. */
    INSUFFICIENT_HOLDINGS,

    /** The account was suspended or closed between acceptance and execution. */
    ACCOUNT_NOT_ACTIVE
}

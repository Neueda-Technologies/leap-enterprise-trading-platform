package com.tradingplatform.tradeapi.service;

/**
 * A guarded update affected no rows, so another transaction won the race.
 *
 * <p>Catalogue code {@code ORD-409}, HTTP 409. The catalogue is a closed enumeration and has no code
 * of its own for a concurrency conflict, so the conflict code carries it. That is the right status:
 * the request was valid, the state moved underneath it, and the correct client behaviour is to retry.
 *
 * <p>This is not an error to suppress. A version predicate that matches nothing means the balance the
 * update was computed from is stale, and applying it anyway is a lost update: two orders debit the
 * same account, one of the debits disappears, and nothing in the system says so until somebody
 * reconciles the cash.
 */
public class ConcurrentUpdateException extends RuntimeException {

    /** Catalogue code raised by this exception. */
    public static final String ERROR_CODE = "ORD-409";

    private final transient String detail;

    public ConcurrentUpdateException(String detail) {
        super("Order could not be recorded, please retry");
        this.detail = detail;
    }

    /** Which guarded update lost. For the server log only. */
    public String detail() {
        return detail;
    }
}

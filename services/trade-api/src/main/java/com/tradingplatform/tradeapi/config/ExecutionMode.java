package com.tradingplatform.tradeapi.config;

/**
 * How the service resolves an accepted order.
 *
 * <p>The platform holds both behaviours at once because the build passes through both. The switch is
 * the property {@code trading.execution-mode}.
 *
 * <p>Keeping the Sprint 6 behaviour available after Sprint 7 is not sentiment. It lets a team run the
 * API without a broker while they are debugging something else, and it makes the difference between
 * the two worlds a configuration change a participant can toggle and observe rather than a paragraph
 * they are asked to believe.
 */
public enum ExecutionMode {

    /**
     * Sprint 6. No Trade Executor exists, so the API validates, records, fills and updates cash and
     * position inside one request, and returns {@code FILLED}.
     *
     * <p>This is only correct while nothing real is happening. It ties the customer's HTTP request to
     * the lifetime of the execution, so a slow venue becomes a slow API and a restart mid-request
     * loses the trade.
     */
    SYNC,

    /**
     * Sprint 7 onwards, and the default. The API validates, records the order as {@code NEW},
     * publishes it to the {@code orders} topic and returns {@code NEW}. The Trade Executor prices it
     * against a live quote, applies the fill rules, updates order, cash and position in one
     * transaction, and publishes the outcome to {@code trade-events}.
     */
    ASYNC
}

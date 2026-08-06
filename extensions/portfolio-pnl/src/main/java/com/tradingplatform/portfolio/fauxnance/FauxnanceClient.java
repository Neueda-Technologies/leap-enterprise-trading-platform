package com.tradingplatform.portfolio.fauxnance;

import java.util.List;
import java.util.Map;

/**
 * Talks to the Fauxnance API. The only two operations this service needs: a batch
 * quote lookup, and a quota check for the health endpoint.
 */
public interface FauxnanceClient {

    /**
     * Calls {@code GET /quotes?symbols=A,B,C}, batched at up to
     * {@code fauxnance.quote-batch-size} symbols per call (25, per the contract), so
     * that ten held symbols cost one unit of the daily quota rather than ten.
     *
     * @return a quote per symbol that was successfully priced. A symbol missing from
     *     the result means Fauxnance could not price it; the caller decides whether
     *     that makes the response partial or unavailable.
     */
    Map<String, Quote> getQuotes(List<String> symbols);

    /** Calls {@code GET /usage}. Returns null if the call fails; the health check degrades, it does not throw. */
    Integer getQuotaRemaining();
}

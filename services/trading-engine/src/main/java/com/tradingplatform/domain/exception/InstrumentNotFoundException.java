package com.tradingplatform.domain.exception;

/**
 * Business rule 3. The symbol is unknown, or it is known and not tradable.
 *
 * <p>Catalogue code {@code INS-404}, mapped to HTTP 404 by the Trade REST API. One code covers both
 * cases on purpose. An instrument is suspended by setting {@code instruments.tradable} to false
 * rather than by deleting the row, because deleting it would orphan the order history, and a caller
 * has no need to know which of the two situations it hit.
 */
public class InstrumentNotFoundException extends TradingException {

    /** Catalogue code raised by this exception. */
    public static final String ERROR_CODE = "INS-404";

    private final transient String symbol;

    public InstrumentNotFoundException(String symbol) {
        super(ERROR_CODE, "Instrument not found");
        this.symbol = symbol;
    }

    /** The symbol that was requested. For logging, never for the response body. */
    public String symbol() {
        return symbol;
    }
}

package com.tradingplatform.domain.exception;

/**
 * Base type for every business rule failure in the trading domain.
 *
 * <p>Two design points carry the weight here.
 *
 * <p>First, the exception carries an {@code errorCode} from the platform error catalogue, not an
 * HTTP status. The domain has no opinion about HTTP. The Trade REST API maps the code to a status
 * in one place, its {@code @ControllerAdvice}, and any other consumer of this library maps it
 * somewhere else. Putting the status here would drag the web layer into the domain.
 *
 * <p>Second, the message is the catalogue message and nothing more. It never contains an account
 * key, a symbol, a SQL fragment or a class name, because the message is returned to the caller.
 * Values needed for an investigation are held as typed fields and logged on the server side. Leaking
 * internal detail in an error body is OWASP A05.
 *
 * <p>The hierarchy is unchecked. A business rule failure is not something a caller can recover from
 * by catching it locally: it terminates the request and becomes a response.
 */
public abstract class TradingException extends RuntimeException {

    private final String errorCode;

    protected TradingException(String errorCode, String message) {
        super(message);
        this.errorCode = errorCode;
    }

    /**
     * The platform error catalogue code, for example {@code ACC-404}. The value the client branches
     * on.
     */
    public String errorCode() {
        return errorCode;
    }
}

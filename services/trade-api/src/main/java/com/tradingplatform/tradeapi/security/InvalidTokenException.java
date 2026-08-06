package com.tradingplatform.tradeapi.security;

/**
 * A token was missing, malformed, expired, wrongly signed, or carried claims the platform does not
 * accept.
 *
 * <p>Catalogue code {@code AUTH-401}, HTTP 401.
 *
 * <p>One exception covers every cause, and the response body is identical for all of them. Telling a
 * caller that the signature was wrong rather than that the token had expired hands an attacker a
 * free oracle. The cause is recorded in {@link #reason()} for the log and never leaves the process.
 */
public class InvalidTokenException extends RuntimeException {

    /** Catalogue code raised by this exception. */
    public static final String ERROR_CODE = "AUTH-401";

    private final transient String reason;

    public InvalidTokenException(String reason) {
        super("Unauthorised");
        this.reason = reason;
    }

    public InvalidTokenException(String reason, Throwable cause) {
        super("Unauthorised", cause);
        this.reason = reason;
    }

    /** Why verification failed. For the server log only. */
    public String reason() {
        return reason;
    }
}

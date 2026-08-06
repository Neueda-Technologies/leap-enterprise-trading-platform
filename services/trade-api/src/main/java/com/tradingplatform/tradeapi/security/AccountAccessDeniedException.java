package com.tradingplatform.tradeapi.security;

/**
 * A verified token addressed an account it does not own.
 *
 * <p>Catalogue code {@code ACC-403}, HTTP 403. A token proves who you are, not what you may reach.
 * Skipping this check is OWASP A01, broken access control, and it is the most common serious defect
 * in a first JWT integration: the token is verified, the caller is authenticated, and then the
 * account key is taken from the request and used unquestioned.
 *
 * <p>The message is {@code Account not active}, identical to the refusal a suspended account gets.
 * That is deliberate. A different message here would let anyone with one valid token enumerate which
 * account keys exist by reading which of the two answers came back.
 */
public class AccountAccessDeniedException extends RuntimeException {

    /** Catalogue code raised by this exception. */
    public static final String ERROR_CODE = "ACC-403";

    private final transient String subject;
    private final transient Long requestedAccountId;

    public AccountAccessDeniedException(String subject, Long requestedAccountId) {
        super("Account not active");
        this.subject = subject;
        this.requestedAccountId = requestedAccountId;
    }

    /** The {@code sub} claim of the token that was used. For logging. */
    public String subject() {
        return subject;
    }

    /** The account key that was addressed. For logging, never for the response body. */
    public Long requestedAccountId() {
        return requestedAccountId;
    }
}

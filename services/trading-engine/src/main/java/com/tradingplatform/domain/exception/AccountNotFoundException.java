package com.tradingplatform.domain.exception;

/**
 * Business rule 1. No account exists with the requested key.
 *
 * <p>Catalogue code {@code ACC-404}, mapped to HTTP 404 by the Trade REST API.
 */
public class AccountNotFoundException extends TradingException {

    /** Catalogue code raised by this exception. */
    public static final String ERROR_CODE = "ACC-404";

    private final transient Long accountId;

    public AccountNotFoundException(Long accountId) {
        super(ERROR_CODE, "Account not found");
        this.accountId = accountId;
    }

    /** The key that was looked up. For logging, never for the response body. */
    public Long accountId() {
        return accountId;
    }
}

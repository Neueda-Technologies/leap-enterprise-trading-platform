package com.tradingplatform.domain.exception;

import com.tradingplatform.domain.model.AccountStatus;

/**
 * Business rule 2. The account exists but is {@code SUSPENDED} or {@code CLOSED}.
 *
 * <p>Catalogue code {@code ACC-403}, mapped to HTTP 403 by the Trade REST API. The same code is
 * returned when a valid token addresses an account it does not own: a token proves who you are, not
 * what you may reach, and both failures deserve the same opaque answer.
 */
public class AccountNotActiveException extends TradingException {

    /** Catalogue code raised by this exception. */
    public static final String ERROR_CODE = "ACC-403";

    private final transient Long accountId;
    private final transient AccountStatus status;

    public AccountNotActiveException(Long accountId, AccountStatus status) {
        super(ERROR_CODE, "Account not active");
        this.accountId = accountId;
        this.status = status;
    }

    /** The key that was addressed. For logging, never for the response body. */
    public Long accountId() {
        return accountId;
    }

    /**
     * The status that caused the refusal. For logging. The response does not distinguish
     * {@code SUSPENDED} from {@code CLOSED}.
     */
    public AccountStatus status() {
        return status;
    }
}

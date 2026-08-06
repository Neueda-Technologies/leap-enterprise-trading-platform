package com.tradingplatform.portfolio.exception;

import org.springframework.http.HttpStatus;

/** ACC-404: no account exists with the given key. */
public class AccountNotFoundException extends ApiException {

    public AccountNotFoundException(long accountId) {
        super("ACC-404", HttpStatus.NOT_FOUND, "Account not found");
    }
}

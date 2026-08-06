package com.tradingplatform.portfolio.exception;

import org.springframework.http.HttpStatus;

/**
 * ACC-403: the token is valid but its {@code accountId} claim does not match the
 * account requested. Returned instead of ACC-404 on purpose, and logged: a customer
 * probing another customer's portfolio is an access-control failure, not a lookup miss.
 */
public class ForbiddenException extends ApiException {

    public ForbiddenException() {
        super("ACC-403", HttpStatus.FORBIDDEN, "Account not accessible");
    }
}

package com.tradingplatform.portfolio.exception;

import org.springframework.http.HttpStatus;

/** AUTH-401: missing, malformed, expired or wrongly signed token. */
public class UnauthorisedException extends ApiException {

    public UnauthorisedException(String message) {
        super("AUTH-401", HttpStatus.UNAUTHORIZED, "Unauthorised");
    }

    public UnauthorisedException() {
        this("Unauthorised");
    }
}

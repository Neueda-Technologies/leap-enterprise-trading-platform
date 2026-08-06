package com.tradingplatform.portfolio.exception;

import org.springframework.http.HttpStatus;

/**
 * Base type for every exception that maps to an entry in the error catalogue
 * described in docs/contracts/portfolio-api.yaml. {@link com.tradingplatform.portfolio.web.GlobalExceptionHandler}
 * turns one of these into the standard {@code {errorCode, message}} envelope.
 */
public abstract class ApiException extends RuntimeException {

    private final String errorCode;
    private final HttpStatus status;

    protected ApiException(String errorCode, HttpStatus status, String message) {
        super(message);
        this.errorCode = errorCode;
        this.status = status;
    }

    public String getErrorCode() {
        return errorCode;
    }

    public HttpStatus getStatus() {
        return status;
    }
}

package com.tradingplatform.portfolio.exception;

import org.springframework.http.HttpStatus;

/** VAL-422: the request failed field validation, for example {@code from} later than {@code to}. */
public class InvalidInputException extends ApiException {

    public InvalidInputException(String message) {
        super("VAL-422", HttpStatus.UNPROCESSABLE_ENTITY, message);
    }
}

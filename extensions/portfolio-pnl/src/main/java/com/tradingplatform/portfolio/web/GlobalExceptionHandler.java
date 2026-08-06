package com.tradingplatform.portfolio.web;

import com.tradingplatform.portfolio.exception.ApiException;
import com.tradingplatform.portfolio.web.dto.ErrorResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * Turns the catalogued exceptions into the standard {@code {errorCode, message}}
 * envelope from docs/contracts/portfolio-api.yaml. {@link com.tradingplatform.portfolio.exception.ForbiddenException}
 * (ACC-403) is logged at warn level here: the contract calls out that a customer
 * probing another customer's portfolio must be logged, not only rejected.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ErrorResponse> handleApiException(ApiException e) {
        if ("ACC-403".equals(e.getErrorCode())) {
            log.warn("Access-control failure: {}", e.getMessage());
        }
        return ResponseEntity.status(e.getStatus()).body(new ErrorResponse(e.getErrorCode(), e.getMessage()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(MethodArgumentNotValidException e) {
        return ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY).body(new ErrorResponse("VAL-422", "Invalid input"));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleUnexpected(Exception e) {
        log.error("Unhandled exception", e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(new ErrorResponse("INTERNAL-500", "Internal error"));
    }
}

package com.tradingplatform.tradeapi.web;

import com.tradingplatform.domain.exception.AccountNotActiveException;
import com.tradingplatform.domain.exception.AccountNotFoundException;
import com.tradingplatform.domain.exception.DuplicateOrderException;
import com.tradingplatform.domain.exception.InstrumentNotFoundException;
import com.tradingplatform.domain.exception.InsufficientFundsException;
import com.tradingplatform.domain.exception.InsufficientHoldingsException;
import com.tradingplatform.domain.exception.InvalidOrderException;
import com.tradingplatform.domain.exception.OrderNotCancellableException;
import com.tradingplatform.domain.exception.OrderNotFoundException;
import com.tradingplatform.domain.exception.TradingException;
import com.tradingplatform.tradeapi.security.AccountAccessDeniedException;
import com.tradingplatform.tradeapi.security.InvalidTokenException;
import com.tradingplatform.tradeapi.service.ConcurrentUpdateException;
import com.tradingplatform.tradeapi.web.dto.ErrorResponse;
import jakarta.validation.ConstraintViolationException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

/**
 * Turns every exception into the platform error envelope.
 *
 * <p>One place, not thirty. A controller that catches its own exceptions produces a catalogue that
 * drifts endpoint by endpoint until two routes return different codes for the same failure, and the
 * Angular UI grows a special case for each.
 *
 * <p>The mapping table below is the contract's error catalogue. Note that the code and the status are
 * not in one-to-one correspondence: {@code ORD-409} appears with 404 and with 409, which is exactly
 * why the contract tells clients to branch on {@code errorCode}, never on the status alone.
 *
 * <table>
 *   <caption>Mapping</caption>
 *   <tr><th>Exception</th><th>Code</th><th>Status</th></tr>
 *   <tr><td>{@code AccountNotFoundException}</td><td>ACC-404</td><td>404</td></tr>
 *   <tr><td>{@code AccountNotActiveException}</td><td>ACC-403</td><td>403</td></tr>
 *   <tr><td>{@code AccountAccessDeniedException}</td><td>ACC-403</td><td>403</td></tr>
 *   <tr><td>{@code InstrumentNotFoundException}</td><td>INS-404</td><td>404</td></tr>
 *   <tr><td>{@code InsufficientFundsException}</td><td>ORD-400</td><td>400</td></tr>
 *   <tr><td>{@code InsufficientHoldingsException}</td><td>ORD-409</td><td>409</td></tr>
 *   <tr><td>{@code DuplicateOrderException}</td><td>ORD-409</td><td>409</td></tr>
 *   <tr><td>{@code OrderNotCancellableException}</td><td>ORD-409</td><td>409</td></tr>
 *   <tr><td>{@code ConcurrentUpdateException}</td><td>ORD-409</td><td>409</td></tr>
 *   <tr><td>{@code OrderNotFoundException}</td><td>ORD-409</td><td>404</td></tr>
 *   <tr><td>{@code InvalidOrderException}, binding failures</td><td>VAL-422</td><td>422</td></tr>
 *   <tr><td>{@code InvalidTokenException}</td><td>AUTH-401</td><td>401</td></tr>
 *   <tr><td>anything else</td><td>VAL-422</td><td>500, with no code</td></tr>
 * </table>
 *
 * <p>Nothing in a response body carries a stack trace, a SQL fragment, a class name or an internal
 * identifier. The detail goes to the log, where the operator can reach it and the caller cannot.
 * Leaking it into the body is OWASP A05, and an exception message is the most common way it happens.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    private static final String CODE_INVALID_INPUT = "VAL-422";
    private static final String MESSAGE_INVALID_INPUT = "Invalid input";

    // ---- 404 -------------------------------------------------------------------------------

    @ExceptionHandler(AccountNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleAccountNotFound(AccountNotFoundException e) {
        log.info("Account not found accountId={}", e.accountId());
        return envelope(HttpStatus.NOT_FOUND, e);
    }

    @ExceptionHandler(InstrumentNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleInstrumentNotFound(InstrumentNotFoundException e) {
        log.info("Instrument not found or not tradable symbol={}", e.symbol());
        return envelope(HttpStatus.NOT_FOUND, e);
    }

    /**
     * 404 with {@code ORD-409}. The pairing comes straight from the contract: the catalogue is a
     * closed enumeration and has no order-not-found code.
     */
    @ExceptionHandler(OrderNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleOrderNotFound(OrderNotFoundException e) {
        log.info("Order not found orderId={}", e.orderId());
        return envelope(HttpStatus.NOT_FOUND, e);
    }

    // ---- 403 -------------------------------------------------------------------------------

    @ExceptionHandler(AccountNotActiveException.class)
    public ResponseEntity<ErrorResponse> handleAccountNotActive(AccountNotActiveException e) {
        log.info("Account not active accountId={} status={}", e.accountId(), e.status());
        return envelope(HttpStatus.FORBIDDEN, e);
    }

    @ExceptionHandler(AccountAccessDeniedException.class)
    public ResponseEntity<ErrorResponse> handleAccessDenied(AccountAccessDeniedException e) {
        // Worth a warning rather than an info: a valid token reaching for an account it does not own
        // is either a client defect or an attempt.
        log.warn("Access denied subject={} requestedAccountId={}", e.subject(), e.requestedAccountId());
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(new ErrorResponse(AccountAccessDeniedException.ERROR_CODE, e.getMessage()));
    }

    // ---- 400 and 409 -----------------------------------------------------------------------

    @ExceptionHandler(InsufficientFundsException.class)
    public ResponseEntity<ErrorResponse> handleInsufficientFunds(InsufficientFundsException e) {
        log.info("Insufficient funds required={} available={}", e.required(), e.available());
        return envelope(HttpStatus.BAD_REQUEST, e);
    }

    @ExceptionHandler(InsufficientHoldingsException.class)
    public ResponseEntity<ErrorResponse> handleInsufficientHoldings(InsufficientHoldingsException e) {
        log.info("Insufficient holdings symbol={} requested={} held={}",
                e.symbol(), e.requested(), e.held());
        return envelope(HttpStatus.CONFLICT, e);
    }

    @ExceptionHandler(DuplicateOrderException.class)
    public ResponseEntity<ErrorResponse> handleDuplicateOrder(DuplicateOrderException e) {
        log.info("Duplicate order idempotencyKey={}", e.idempotencyKey());
        return envelope(HttpStatus.CONFLICT, e);
    }

    @ExceptionHandler(OrderNotCancellableException.class)
    public ResponseEntity<ErrorResponse> handleNotCancellable(OrderNotCancellableException e) {
        log.info("Order not cancellable orderId={} status={}", e.orderId(), e.status());
        return envelope(HttpStatus.CONFLICT, e);
    }

    @ExceptionHandler(ConcurrentUpdateException.class)
    public ResponseEntity<ErrorResponse> handleConcurrentUpdate(ConcurrentUpdateException e) {
        log.warn("Optimistic lock conflict detail={}", e.detail());
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(new ErrorResponse(ConcurrentUpdateException.ERROR_CODE, e.getMessage()));
    }

    // ---- 422 -------------------------------------------------------------------------------

    @ExceptionHandler(InvalidOrderException.class)
    public ResponseEntity<ErrorResponse> handleInvalidOrder(InvalidOrderException e) {
        log.info("Invalid order field={} detail={}", e.field(), e.detail());
        return envelope(HttpStatus.UNPROCESSABLE_ENTITY, e);
    }

    /**
     * Bean Validation on the request body.
     *
     * <p>422 rather than the 400 Spring returns by default, because the contract says 422. The body
     * is the platform envelope, not Spring's problem-detail document, for the same reason.
     *
     * <p>The individual field messages go to the log and not to the caller. They name internal field
     * constraints, and the contract's error catalogue has one message for the whole class of failure.
     */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleBodyValidation(MethodArgumentNotValidException e) {
        String detail = e.getBindingResult().getFieldErrors().stream()
                .map(error -> error.getField() + " " + error.getDefaultMessage())
                .reduce((left, right) -> left + "; " + right)
                .orElse("no field detail");
        log.info("Request body failed validation detail={}", detail);
        return invalidInput();
    }

    /** Bean Validation on a path variable or a query parameter. */
    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ErrorResponse> handleParameterValidation(ConstraintViolationException e) {
        log.info("Request parameter failed validation detail={}", e.getMessage());
        return invalidInput();
    }

    /**
     * A malformed body, an unparseable enum, or a path variable that is not a UUID.
     *
     * <p>The order identifier in {@code DELETE /api/v1/orders/{id}} is a UUID without the {@code ORD-}
     * display prefix. Sending the prefixed form lands here.
     */
    @ExceptionHandler({HttpMessageNotReadableException.class,
            MethodArgumentTypeMismatchException.class,
            MissingServletRequestParameterException.class})
    public ResponseEntity<ErrorResponse> handleUnreadableRequest(Exception e) {
        log.info("Request could not be bound type={}", e.getClass().getSimpleName());
        return invalidInput();
    }

    // ---- 401 -------------------------------------------------------------------------------

    /**
     * Reached only when a token failure escapes the filter, which the filter is written to prevent.
     * Kept because a handler that exists and never fires is cheaper than the response body a caller
     * gets when one does not.
     */
    @ExceptionHandler(InvalidTokenException.class)
    public ResponseEntity<ErrorResponse> handleInvalidToken(InvalidTokenException e) {
        log.warn("Token rejected inside the dispatcher reason={}", e.reason());
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(ErrorResponse.unauthorised());
    }

    // ---- anything else ---------------------------------------------------------------------

    /**
     * The last resort. A 500 with no error code, because the catalogue describes failures the
     * platform understands and this is not one of them.
     *
     * <p>Logged at error with the stack trace, which is the only place the stack trace goes.
     */
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleUnexpected(Exception e) {
        log.error("Unhandled exception", e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(new ErrorResponse("INTERNAL", "Internal error"));
    }

    private static ResponseEntity<ErrorResponse> envelope(HttpStatus status, TradingException e) {
        return ResponseEntity.status(status)
                .body(new ErrorResponse(e.errorCode(), e.getMessage()));
    }

    private static ResponseEntity<ErrorResponse> invalidInput() {
        return ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY)
                .body(new ErrorResponse(CODE_INVALID_INPUT, MESSAGE_INVALID_INPUT));
    }
}

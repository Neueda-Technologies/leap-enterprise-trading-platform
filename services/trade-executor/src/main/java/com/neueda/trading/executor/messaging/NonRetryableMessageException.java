package com.neueda.trading.executor.messaging;

/**
 * A message that will fail identically on every redelivery: bad JSON, a missing required field, or
 * an order identifier that does not exist in Postgres. It goes to the dead-letter topic on the
 * first attempt rather than consuming the retry budget and blocking its partition.
 */
public class NonRetryableMessageException extends RuntimeException {

    public NonRetryableMessageException(String message) {
        super(message);
    }

    public NonRetryableMessageException(String message, Throwable cause) {
        super(message, cause);
    }
}

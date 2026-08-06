package com.neueda.trading.executor.messaging;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.neueda.trading.executor.domain.Side;
import java.math.BigDecimal;
import java.util.UUID;

/**
 * The {@code ORDER_PLACED} payload. Field names and types are fixed by
 * {@code docs/contracts/kafka-topics.md}.
 *
 * <p>Boxed types, not primitives, so that a missing field arrives as null and is caught by
 * {@link #validate()} rather than defaulting silently to zero.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record OrderPlacedPayload(
        UUID orderId,
        Long accountId,
        String symbol,
        Side side,
        Integer quantity,
        BigDecimal price,
        String idempotencyKey,
        String createdOn) {

    /**
     * Rejects a payload that can never be processed, whatever the state of the platform. The caller
     * turns the failure into a dead-letter publication on the first attempt, because retrying a
     * message with no {@code orderId} will fail identically for ever.
     */
    public void validate() {
        require(orderId != null, "orderId is missing");
        require(accountId != null, "accountId is missing");
        require(symbol != null && !symbol.isBlank(), "symbol is missing");
        require(side != null, "side is missing");
        require(quantity != null && quantity > 0, "quantity must be greater than zero");
        require(price != null && price.signum() > 0, "price must be greater than zero");
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new NonRetryableMessageException(message);
        }
    }
}

package com.tradingplatform.domain.dto;

import com.tradingplatform.domain.model.OrderSide;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;

/**
 * A request to place an order, matching {@code PlaceOrderRequest} in
 * {@code contracts/trade-api.yaml}.
 *
 * <p>The DTO lives in the domain rather than in the Trade REST API for one reason: the constraints
 * on it are business constraints, not transport constraints. Quantity greater than zero is business
 * rule 4 and price greater than zero is business rule 5. A second consumer of this library gets the
 * same rules without reimplementing them.
 *
 * <p>Bean Validation annotations are the only framework the architecture permits in the domain.
 * There is nothing here that knows about HTTP.
 *
 * <p>Validation and the business rules overlap deliberately. Bean Validation is a syntactic gate that
 * runs before the request reaches the service, and it rejects a malformed body with {@code VAL-422}
 * without touching the database. {@link com.tradingplatform.domain.service.OrderPlacementService}
 * re-checks rules 4 and 5, because the domain must hold for a caller that never ran a validator.
 *
 * @param accountId      the numeric account key, {@code accounts.id}, not the string business
 *                       reference
 * @param symbol         instrument symbol in the Fauxnance scheme
 * @param side           BUY or SELL
 * @param quantity       whole units, business rule 4
 * @param price          limit price per unit to two decimal places, business rule 5
 * @param idempotencyKey client-generated unique request identifier, business rule 8
 */
public record PlaceOrderRequest(

        @NotNull(message = "accountId is required")
        @Min(value = 1, message = "accountId must be positive")
        Long accountId,

        @NotBlank(message = "symbol is required")
        @Size(max = 20, message = "symbol must be at most 20 characters")
        String symbol,

        @NotNull(message = "side is required")
        OrderSide side,

        @NotNull(message = "quantity is required")
        @Min(value = 1, message = "quantity must be greater than zero")
        Integer quantity,

        @NotNull(message = "price is required")
        @DecimalMin(value = "0.00", inclusive = false, message = "price must be greater than zero")
        @Digits(integer = 16, fraction = 2, message = "price must have at most two decimal places")
        BigDecimal price,

        @NotBlank(message = "idempotencyKey is required")
        @Size(min = 8, max = 100, message = "idempotencyKey must be between 8 and 100 characters")
        String idempotencyKey) {
}

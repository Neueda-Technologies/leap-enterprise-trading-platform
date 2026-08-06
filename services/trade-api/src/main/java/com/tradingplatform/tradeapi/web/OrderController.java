package com.tradingplatform.tradeapi.web;

import com.tradingplatform.domain.dto.PlaceOrderRequest;
import com.tradingplatform.tradeapi.security.AuthenticatedUser;
import com.tradingplatform.tradeapi.service.OrderService;
import com.tradingplatform.tradeapi.web.dto.ErrorResponse;
import com.tradingplatform.tradeapi.web.dto.OrderResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/**
 * Placing and cancelling orders.
 *
 * <p>The controller does four things and no more: it binds the request, it validates it, it hands it
 * to the service, and it returns what comes back. There is no SQL here, no business rule, and no
 * {@code try} block. Every failure path is a domain exception that
 * {@link GlobalExceptionHandler} turns into the error envelope.
 *
 * <p>The identity comes from a request attribute the JWT filter set, never from the request body.
 * A body that carried the caller's identity would be a body the caller could edit.
 */
@RestController
@RequestMapping(path = "/api/v1/orders", produces = MediaType.APPLICATION_JSON_VALUE)
@Tag(name = "Orders", description = "Placing and cancelling orders.")
public class OrderController {

    private final OrderService orderService;

    public OrderController(OrderService orderService) {
        this.orderService = orderService;
    }

    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE)
    @Operation(
            operationId = "placeOrder",
            summary = "Place an order",
            description = """
                    Validates the request against business rules 1 to 8 and records the order.
                    Returns NEW once the Trade Executor exists, or the terminal status when the
                    service fills synchronously.

                    Retrying with the same idempotencyKey is not a way to poll for status. It returns
                    ORD-409. Poll GET /api/v1/accounts/{id}/orders instead.""")
    @ApiResponse(responseCode = "200", description = "Order accepted and recorded.")
    @ApiResponse(responseCode = "400", description = "Insufficient funds.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    @ApiResponse(responseCode = "401", description = "Missing, malformed, expired or wrongly signed token.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    @ApiResponse(responseCode = "403", description = "Account not active, or not reachable with this token.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    @ApiResponse(responseCode = "404", description = "The account or the instrument does not exist.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    @ApiResponse(responseCode = "409", description = "Insufficient holdings, or the idempotency key has been used.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    @ApiResponse(responseCode = "422", description = "The request failed field validation.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    public OrderResponse placeOrder(
            @Valid @RequestBody PlaceOrderRequest request,
            @RequestAttribute(AuthenticatedUser.ATTRIBUTE) AuthenticatedUser user) {

        return orderService.placeOrder(request, user);
    }

    /**
     * @param id the order UUID, without the {@code ORD-} display prefix. The contract is explicit
     *           about that, so this endpoint is too: a value that is not a UUID is {@code VAL-422}.
     */
    @DeleteMapping("/{id}")
    @Operation(
            operationId = "cancelOrder",
            summary = "Cancel a working order",
            description = """
                    Cancels an order that is still NEW and returns the updated order. An order that is
                    already FILLED, REJECTED or CANCELLED cannot be cancelled and returns ORD-409.

                    The cancellation is a state transition guarded inside the database transaction.""")
    @ApiResponse(responseCode = "200", description = "Order cancelled.")
    @ApiResponse(responseCode = "401", description = "Missing, malformed, expired or wrongly signed token.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    @ApiResponse(responseCode = "403", description = "Account not active, or not reachable with this token.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    @ApiResponse(responseCode = "404", description = "No order exists with that identifier.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    @ApiResponse(responseCode = "409", description = "The order is not in a cancellable state.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    public OrderResponse cancelOrder(
            @PathVariable("id") UUID id,
            @RequestAttribute(AuthenticatedUser.ATTRIBUTE) AuthenticatedUser user) {

        return orderService.cancelOrder(id, user);
    }
}

package com.tradingplatform.tradeapi.web.dto;

import com.tradingplatform.domain.model.Order;
import com.tradingplatform.domain.model.OrderSide;
import com.tradingplatform.domain.model.OrderStatus;
import io.swagger.v3.oas.annotations.media.Schema;

import java.math.BigDecimal;

/**
 * The response to placing or cancelling an order.
 *
 * <p>{@code status} is {@code NEW} when execution is asynchronous and terminal when the service
 * fills in process. A client must handle both, because the platform passes through both and the
 * contract permits both.
 *
 * <p>{@code message} is for display. Never branch on it. Branch on {@code status}, or on
 * {@code errorCode} when the response is an error.
 *
 * @param orderId  the order identifier, displayed with an {@code ORD-} prefix over the stored UUID
 * @param status   NEW, FILLED, REJECTED or CANCELLED
 * @param message  human-readable outcome, for display only
 * @param symbol   the instrument
 * @param side     BUY or SELL
 * @param quantity whole units
 * @param price    the limit price submitted
 */
@Schema(name = "OrderResponse")
public record OrderResponse(

        @Schema(example = "ORD-6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e") String orderId,

        OrderStatus status,

        @Schema(example = "Order accepted") String message,

        @Schema(example = "ACME") String symbol,

        OrderSide side,

        @Schema(example = "100") int quantity,

        @Schema(example = "25.50") BigDecimal price) {

    /** Display prefix carried on the identifier in every response. */
    public static final String ORDER_ID_PREFIX = "ORD-";

    public static OrderResponse of(Order order, String message) {
        return new OrderResponse(
                ORDER_ID_PREFIX + order.getId(),
                order.getStatus(),
                message,
                order.getSymbol(),
                order.getSide(),
                order.getQuantity(),
                order.getPrice());
    }
}

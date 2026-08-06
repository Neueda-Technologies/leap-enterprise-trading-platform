package com.tradingplatform.tradeapi.web.dto;

import com.tradingplatform.domain.model.Order;
import com.tradingplatform.domain.model.OrderSide;
import com.tradingplatform.domain.model.OrderStatus;
import io.swagger.v3.oas.annotations.media.Schema;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * One row of the blotter.
 *
 * <p>Two prices, and they are not the same thing. {@code price} is the limit the customer submitted.
 * {@code executedPrice} is what the Trade Executor achieved, and it is null until the order is
 * {@code FILLED}. A report that treats the limit as the traded price is wrong, and once execution is
 * asynchronous the two routinely differ.
 *
 * @param orderId       the identifier, with the display prefix
 * @param accountId     the numeric account key
 * @param symbol        the instrument
 * @param side          BUY or SELL
 * @param quantity      whole units
 * @param price         the limit price submitted with the order
 * @param executedPrice the price the fill was achieved at, null until FILLED
 * @param status        NEW, FILLED, REJECTED or CANCELLED
 * @param idempotencyKey the client key the order was accepted under
 * @param createdOn     when the order was recorded
 */
@Schema(name = "OrderHistoryEntry")
public record OrderHistoryEntry(

        String orderId,
        Long accountId,
        String symbol,
        OrderSide side,
        int quantity,
        BigDecimal price,
        BigDecimal executedPrice,
        OrderStatus status,
        String idempotencyKey,
        Instant createdOn) {

    public static OrderHistoryEntry of(Order order) {
        return new OrderHistoryEntry(
                OrderResponse.ORDER_ID_PREFIX + order.getId(),
                order.getAccountId(),
                order.getSymbol(),
                order.getSide(),
                order.getQuantity(),
                order.getPrice(),
                order.getExecutedPrice(),
                order.getStatus(),
                order.getIdempotencyKey(),
                order.getCreatedOn());
    }
}

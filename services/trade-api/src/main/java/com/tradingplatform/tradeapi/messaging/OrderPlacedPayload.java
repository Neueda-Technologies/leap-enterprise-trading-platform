package com.tradingplatform.tradeapi.messaging;

import com.tradingplatform.domain.model.Order;
import com.tradingplatform.domain.model.OrderSide;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * The {@code ORDER_PLACED} payload on the {@code orders} topic.
 *
 * <p>{@code orders} is a work queue with exactly one consumer group, the Trade Executor. Adding a
 * second group means two services executing the same order. Anything else that needs to know an
 * order was placed reads {@code trade-events}.
 *
 * <p>Nothing here identifies a person. The customer's name is on the account row and stays there.
 * Topics are retained for days and read by services that have no need for it.
 *
 * @param orderId        matches {@code orders.id} in Postgres
 * @param accountId      the numeric account key, also the message key as a string
 * @param symbol         instrument symbol in the Fauxnance scheme
 * @param side           BUY or SELL
 * @param quantity       whole units, greater than zero
 * @param price          limit price per unit
 * @param idempotencyKey the client key that was accepted
 * @param createdOn      when the order was recorded
 */
public record OrderPlacedPayload(
        String orderId,
        Long accountId,
        String symbol,
        OrderSide side,
        int quantity,
        BigDecimal price,
        String idempotencyKey,
        Instant createdOn) {

    /** The only {@code eventType} carried on the {@code orders} topic. */
    public static final String EVENT_TYPE = "ORDER_PLACED";

    public static OrderPlacedPayload of(Order order) {
        return new OrderPlacedPayload(
                order.getId().toString(),
                order.getAccountId(),
                order.getSymbol(),
                order.getSide(),
                order.getQuantity(),
                order.getPrice(),
                order.getIdempotencyKey(),
                order.getCreatedOn());
    }
}

package com.tradingplatform.tradeapi.messaging;

import com.tradingplatform.domain.model.OrderSide;
import com.tradingplatform.domain.model.OrderStatus;
import com.tradingplatform.domain.service.Settlement;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * A payload on the {@code trade-events} topic: the outcome of an order.
 *
 * <p>{@code cashDelta}, {@code positionQuantityAfter} and {@code averageCostAfter} are here so that a
 * consumer can maintain its own projection of the portfolio without querying Postgres. That is what
 * makes the Sprint 10 Portfolio and P&amp;L extension possible without a read dependency on the
 * trading database.
 *
 * <p>The Trade Executor produces {@code ORDER_FILLED} and {@code ORDER_REJECTED} on this topic. The
 * Trade REST API produces {@code ORDER_CANCELLED}, because a customer cancellation arrives at this
 * service and no other process can observe it.
 *
 * @param orderId               the order
 * @param accountId             the numeric account key, also the message key as a string
 * @param symbol                the instrument
 * @param side                  BUY or SELL
 * @param quantity              quantity filled, equal to the ordered quantity
 * @param price                 the limit price from the order
 * @param executedPrice         the quote the fill was priced at, null on reject and cancel
 * @param status                terminal order status
 * @param reason                cause on reject and cancel, null on a fill
 * @param cashDelta             signed change to the cash balance, negative for a buy
 * @param positionQuantityAfter net held quantity after the event
 * @param averageCostAfter      weighted average cost after the event
 * @param executedOn            when the outcome was applied
 */
public record TradeEventPayload(
        String orderId,
        Long accountId,
        String symbol,
        OrderSide side,
        int quantity,
        BigDecimal price,
        BigDecimal executedPrice,
        OrderStatus status,
        String reason,
        BigDecimal cashDelta,
        int positionQuantityAfter,
        BigDecimal averageCostAfter,
        Instant executedOn) {

    /** An order filled in full. */
    public static final String EVENT_TYPE_FILLED = "ORDER_FILLED";

    /** An order refused at execution. A rejection is an event: publish it. */
    public static final String EVENT_TYPE_REJECTED = "ORDER_REJECTED";

    /** An order withdrawn by the customer before execution. */
    public static final String EVENT_TYPE_CANCELLED = "ORDER_CANCELLED";

    /** The {@code reason} carried on a customer cancellation. */
    public static final String REASON_CANCELLED_BY_CUSTOMER = "CANCELLED_BY_CUSTOMER";

    /**
     * Builds the payload from a domain {@link Settlement}. The record's fields were chosen to match
     * this schema, so the translation is a rename and nothing more.
     */
    public static TradeEventPayload of(Settlement settlement, String reason) {
        return new TradeEventPayload(
                settlement.orderId().toString(),
                settlement.accountId(),
                settlement.symbol(),
                settlement.side(),
                settlement.quantity(),
                settlement.price(),
                settlement.executedPrice(),
                settlement.status(),
                reason,
                settlement.cashDelta(),
                settlement.positionQuantityAfter(),
                settlement.averageCostAfter(),
                settlement.executedOn());
    }

    /** The {@code eventType} that matches this payload's status. */
    public String eventType() {
        return switch (status) {
            case FILLED -> EVENT_TYPE_FILLED;
            case REJECTED -> EVENT_TYPE_REJECTED;
            case CANCELLED -> EVENT_TYPE_CANCELLED;
            case NEW -> throw new IllegalStateException(
                    "A working order is not a trade event. Publish ORDER_PLACED to the orders topic.");
        };
    }
}

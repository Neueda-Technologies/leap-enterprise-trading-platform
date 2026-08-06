package com.tradingplatform.domain.service;

import com.tradingplatform.domain.model.OrderSide;
import com.tradingplatform.domain.model.OrderStatus;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

/**
 * The outcome of settling one order: what the cash moved by, and what the holding became.
 *
 * <p>The fields are chosen to match the {@code trade-events} payload exactly. A consumer that reads
 * {@code cashDelta}, {@code positionQuantityAfter} and {@code averageCostAfter} can maintain its own
 * projection of the portfolio without querying Postgres, which is what lets the Sprint 10 Portfolio
 * and P&amp;L extension exist without a read dependency on the trading database.
 *
 * @param orderId               the order that was settled
 * @param accountId             the numeric account key
 * @param symbol                the instrument
 * @param side                  BUY or SELL
 * @param quantity              quantity filled, always the full order quantity
 * @param price                 the limit price from the order
 * @param executedPrice         the price the fill was achieved at
 * @param status                terminal status reached, {@code FILLED} for a settlement
 * @param cashDelta             signed change to the cash balance, negative for a buy
 * @param positionQuantityAfter net held quantity after the fill
 * @param averageCostAfter      weighted average cost after the fill
 * @param executedOn            when the fill was applied
 */
public record Settlement(
        UUID orderId,
        Long accountId,
        String symbol,
        OrderSide side,
        int quantity,
        BigDecimal price,
        BigDecimal executedPrice,
        OrderStatus status,
        BigDecimal cashDelta,
        int positionQuantityAfter,
        BigDecimal averageCostAfter,
        Instant executedOn) {
}

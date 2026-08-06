package com.neueda.trading.executor.messaging;

import com.neueda.trading.executor.domain.OrderStatus;
import com.neueda.trading.executor.domain.Side;
import java.math.BigDecimal;

/**
 * The {@code trade-events} payload, exactly as contracted.
 *
 * <p>{@code cashDelta}, {@code positionQuantityAfter} and {@code averageCostAfter} are carried so
 * that a consumer can maintain its own portfolio projection without reading Postgres. They are
 * populated on a rejection too, where the deltas are zero and the position figures are the
 * unchanged current state. A consumer must be able to apply every event it sees.
 */
public record TradeEventPayload(
        String orderId,
        long accountId,
        String symbol,
        Side side,
        int quantity,
        BigDecimal price,
        BigDecimal executedPrice,
        OrderStatus status,
        String reason,
        BigDecimal cashDelta,
        int positionQuantityAfter,
        BigDecimal averageCostAfter,
        String executedOn) {
}

package com.neueda.trading.executor.persistence;

import com.neueda.trading.executor.domain.OrderStatus;
import com.neueda.trading.executor.domain.Side;
import java.math.BigDecimal;
import java.util.UUID;

/** The columns of {@code orders} the executor reads. */
public record OrderRow(
        UUID id,
        long accountId,
        String symbol,
        Side side,
        int quantity,
        BigDecimal price,
        OrderStatus status) {
}

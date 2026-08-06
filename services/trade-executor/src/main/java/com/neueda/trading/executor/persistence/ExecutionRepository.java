package com.neueda.trading.executor.persistence;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

/**
 * Every statement the executor issues against the operational schema.
 *
 * <p>The two {@code mark} methods carry the guarded transition. They update
 * {@code WHERE id = ? AND status = 'NEW'} and return the affected row count, so a caller that gets
 * zero knows another delivery of the same message already settled the order. That is the platform's
 * chosen idempotency mechanism, and it holds under concurrency because the database serialises the
 * update.
 */
public interface ExecutionRepository {

    Optional<OrderRow> findOrder(UUID orderId);

    /** False when the instrument is suspended, and also when it does not exist at all. */
    boolean isTradable(String symbol);

    Optional<AccountRow> findAccount(long accountId);

    /** Never empty: an account with no holding in the symbol reads as a flat position. */
    PositionRow findPosition(long accountId, String symbol);

    /** @return rows affected: 1 on success, 0 when the order was no longer NEW. */
    int markFilled(UUID orderId, BigDecimal executedPrice, Instant executedOn);

    /** @return rows affected: 1 on success, 0 when the order was no longer NEW. */
    int markRejected(UUID orderId, String reason, Instant executedOn);

    /**
     * Writes the new cash balance under the optimistic lock.
     *
     * @throws OptimisticLockConflictException when another writer moved the version first
     */
    void updateCashBalance(long accountId, BigDecimal newBalance, int expectedVersion, Instant now);

    void upsertPosition(long accountId, String symbol, int quantity, BigDecimal averageCost);
}

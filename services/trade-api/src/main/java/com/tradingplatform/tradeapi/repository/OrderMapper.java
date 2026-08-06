package com.tradingplatform.tradeapi.repository;

import com.tradingplatform.domain.model.Order;
import com.tradingplatform.domain.model.OrderStatus;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Reads and writes {@code orders}.
 *
 * <p>There is no delete. The table is the audit trail, the application role has no {@code DELETE}
 * grant on it, and a rejected order is a row that stays. An order only ever moves from {@code NEW} to
 * a terminal status.
 */
@Mapper
public interface OrderMapper {

    /**
     * Records an accepted order.
     *
     * <p>A duplicate {@code idempotency_key} raises a unique constraint violation, which Spring
     * translates to {@code DuplicateKeyException} and the service turns into {@code ORD-409}. That is
     * business rule 8, and the constraint is the whole of it. Do not add a select before this insert:
     * two concurrent requests carrying the same key both find no row, both pass, and both insert.
     */
    int insert(@Param("order") Order order);

    /**
     * Loads one order.
     *
     * @return the order, or null when no row exists
     */
    Order findById(@Param("id") UUID id);

    /**
     * The blotter: every order on the account, newest first, including rejected and cancelled ones.
     *
     * <p>Served by {@code ix_orders_account_created}. The filters are optional and each is applied
     * only when supplied, which is what the {@code <if>} blocks in the mapper XML do. This is the
     * one place dynamic SQL earns its place: the alternative is four near-identical statements.
     *
     * @param status restrict to one status, or null for all
     * @param from   include orders created on or after this instant, or null
     * @param to     include orders created on or before this instant, or null
     */
    List<Order> findByAccount(@Param("accountId") Long accountId,
                              @Param("status") OrderStatus status,
                              @Param("from") Instant from,
                              @Param("to") Instant to);

    /**
     * Moves an order from {@code NEW} to {@code FILLED}, guarded on the status.
     *
     * <p>The guard is what stops two executor instances filling the same order. The database
     * serialises the update, so exactly one of them affects a row and the other sees zero and treats
     * the message as already handled. This is the idempotent-handling mechanism the Sprint 7
     * acceptance check demands: replay a consumed message and show the cash balance does not move
     * twice.
     *
     * @return rows affected: 1 when this caller performed the transition, 0 when it was already done
     */
    int fillIfNew(@Param("id") UUID id,
                  @Param("executedPrice") BigDecimal executedPrice,
                  @Param("executedOn") Instant executedOn);

    /**
     * Moves an order from {@code NEW} to {@code CANCELLED}, guarded on the status.
     *
     * <p>Same mechanism, same reason. Reading the status and then updating it races the Trade
     * Executor, which is filling the same row from another process.
     *
     * @return rows affected: 1 when the order was cancelled, 0 when it was not cancellable
     */
    int cancelIfNew(@Param("id") UUID id);
}

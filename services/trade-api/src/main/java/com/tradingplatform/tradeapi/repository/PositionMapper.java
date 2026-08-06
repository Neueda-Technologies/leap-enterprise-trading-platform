package com.tradingplatform.tradeapi.repository;

import com.tradingplatform.domain.model.Position;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.math.BigDecimal;
import java.util.List;

/**
 * Reads and writes {@code positions}.
 */
@Mapper
public interface PositionMapper {

    /**
     * The holding of one instrument in one account.
     *
     * @return the position, or null when the account holds none of it
     */
    Position find(@Param("accountId") Long accountId, @Param("symbol") String symbol);

    /**
     * Every holding on the account, excluding positions that have been sold down to zero.
     *
     * <p>The zero rows are kept in the table rather than deleted, because the row carries the average
     * cost that a later buy folds into its weighted average, and because deleting and reinserting the
     * same key is more work than updating it.
     */
    List<Position> findByAccount(@Param("accountId") Long accountId);

    /**
     * Writes a holding, inserting it when the account did not hold the instrument before.
     *
     * <p>One statement, using {@code ON CONFLICT} on the composite primary key, rather than a select
     * followed by an insert or an update. The same race applies as everywhere else in this service:
     * two concurrent fills on one account and symbol both find no row and both insert, and one of
     * them fails on the primary key having already lost the value it was carrying.
     */
    int upsert(@Param("accountId") Long accountId,
               @Param("symbol") String symbol,
               @Param("quantity") int quantity,
               @Param("averageCost") BigDecimal averageCost);
}

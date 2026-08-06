package com.tradingplatform.tradeapi.repository;

import com.tradingplatform.domain.model.Account;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * Reads and writes {@code accounts}.
 *
 * <p>Every statement is parameterised. No SQL in this service is built by concatenating a value into
 * a string, and every placeholder in the mapper XML is {@code #{}} rather than {@code ${}}.
 * {@code #{}} becomes a JDBC bind parameter and cannot change the shape of the statement;
 * {@code ${}} is textual substitution and is SQL injection with extra steps. There is one legitimate
 * use of {@code ${}}, dynamic identifiers such as a sort column, and this service has none.
 */
@Mapper
public interface AccountMapper {

    /**
     * Loads an account by its numeric key.
     *
     * @return the account, or null when no row exists. Null is business rule 1.
     */
    Account findById(@Param("id") Long id);

    /**
     * Writes a new cash balance, guarded by the optimistic lock.
     *
     * <p>The {@code WHERE version = :expectedVersion} clause is what makes concurrent order placement
     * on one account safe without a pessimistic lock. Zero rows affected means another transaction
     * committed a change to the row between the read and this write, so the balance this update was
     * computed from is stale and the caller must not apply it.
     *
     * @param expectedVersion the version the account was read at
     * @return rows affected: 1 when the write won, 0 when it lost
     */
    int updateCashBalance(@Param("id") Long id,
                          @Param("cashBalance") BigDecimal cashBalance,
                          @Param("expectedVersion") int expectedVersion,
                          @Param("lastUpdated") Instant lastUpdated);
}

package com.neueda.trading.executor.persistence;

import com.neueda.trading.executor.domain.OrderStatus;
import com.neueda.trading.executor.domain.Side;
import java.math.BigDecimal;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

/**
 * Plain JDBC against the schema in {@code docs/contracts/database-schema.sql}. Every statement is
 * parameterised; nothing here builds SQL by concatenation.
 *
 * <p>Timestamps are written as UTC wall-clock values because the specified columns are
 * {@code TIMESTAMP} without a zone. Converting through the JVM default zone instead would make the
 * stored value depend on where the container happens to run.
 */
@Repository
public class JdbcExecutionRepository implements ExecutionRepository {

    private static final RowMapper<OrderRow> ORDER_MAPPER = JdbcExecutionRepository::mapOrder;
    private static final RowMapper<AccountRow> ACCOUNT_MAPPER = JdbcExecutionRepository::mapAccount;

    private final JdbcTemplate jdbc;

    public JdbcExecutionRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public Optional<OrderRow> findOrder(UUID orderId) {
        List<OrderRow> rows = jdbc.query("""
                SELECT id, account_id, symbol, side, quantity, price, status
                  FROM orders
                 WHERE id = ?
                """, ORDER_MAPPER, orderId);
        return rows.stream().findFirst();
    }

    @Override
    public boolean isTradable(String symbol) {
        List<Boolean> rows = jdbc.query(
                "SELECT tradable FROM instruments WHERE symbol = ?",
                (rs, rowNum) -> rs.getBoolean("tradable"),
                symbol);
        return rows.stream().findFirst().orElse(false);
    }

    @Override
    public Optional<AccountRow> findAccount(long accountId) {
        List<AccountRow> rows = jdbc.query("""
                SELECT id, cash_balance, status, version
                  FROM accounts
                 WHERE id = ?
                """, ACCOUNT_MAPPER, accountId);
        return rows.stream().findFirst();
    }

    @Override
    public PositionRow findPosition(long accountId, String symbol) {
        List<PositionRow> rows = jdbc.query("""
                SELECT account_id, symbol, quantity, average_cost
                  FROM positions
                 WHERE account_id = ? AND symbol = ?
                """,
                (rs, rowNum) -> new PositionRow(
                        rs.getLong("account_id"),
                        rs.getString("symbol"),
                        rs.getInt("quantity"),
                        rs.getBigDecimal("average_cost")),
                accountId, symbol);
        return rows.stream().findFirst().orElseGet(() -> PositionRow.empty(accountId, symbol));
    }

    @Override
    public int markFilled(UUID orderId, BigDecimal executedPrice, Instant executedOn) {
        return jdbc.update("""
                UPDATE orders
                   SET status = 'FILLED', executed_price = ?, executed_on = ?
                 WHERE id = ? AND status = 'NEW'
                """, executedPrice, utc(executedOn), orderId);
    }

    @Override
    public int markRejected(UUID orderId, String reason, Instant executedOn) {
        return jdbc.update("""
                UPDATE orders
                   SET status = 'REJECTED', reject_reason = ?, executed_on = ?
                 WHERE id = ? AND status = 'NEW'
                """, reason, utc(executedOn), orderId);
    }

    @Override
    public void updateCashBalance(long accountId, BigDecimal newBalance, int expectedVersion,
                                  Instant now) {
        int affected = jdbc.update("""
                UPDATE accounts
                   SET cash_balance = ?, version = version + 1, last_updated = ?
                 WHERE id = ? AND version = ?
                """, newBalance, utc(now), accountId, expectedVersion);
        if (affected == 0) {
            throw new OptimisticLockConflictException(accountId, expectedVersion);
        }
    }

    @Override
    public void upsertPosition(long accountId, String symbol, int quantity,
                               BigDecimal averageCost) {
        jdbc.update("""
                INSERT INTO positions (account_id, symbol, quantity, average_cost)
                VALUES (?, ?, ?, ?)
                ON CONFLICT (account_id, symbol)
                DO UPDATE SET quantity = EXCLUDED.quantity, average_cost = EXCLUDED.average_cost
                """, accountId, symbol, quantity, averageCost);
    }

    private static LocalDateTime utc(Instant instant) {
        return LocalDateTime.ofInstant(instant, ZoneOffset.UTC);
    }

    private static OrderRow mapOrder(ResultSet rs, int rowNum) throws SQLException {
        return new OrderRow(
                rs.getObject("id", UUID.class),
                rs.getLong("account_id"),
                rs.getString("symbol"),
                Side.valueOf(rs.getString("side")),
                rs.getInt("quantity"),
                rs.getBigDecimal("price"),
                OrderStatus.valueOf(rs.getString("status")));
    }

    private static AccountRow mapAccount(ResultSet rs, int rowNum) throws SQLException {
        return new AccountRow(
                rs.getLong("id"),
                rs.getBigDecimal("cash_balance"),
                rs.getString("status"),
                rs.getInt("version"));
    }
}

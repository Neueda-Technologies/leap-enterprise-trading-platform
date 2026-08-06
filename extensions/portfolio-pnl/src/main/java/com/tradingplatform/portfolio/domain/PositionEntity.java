package com.tradingplatform.portfolio.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;
import java.math.BigDecimal;

/**
 * Maps {@code positions}, per docs/contracts/database-schema.sql. Read-only from this
 * service: the Trade Executor is the only writer, inside the transaction that fills an
 * order.
 *
 * <p>Quantity and average cost are read directly from this table rather than
 * reconstructed from a Kafka projection. portfolio-api.yaml offers both options
 * ("{@code positions} in Postgres, or a projection maintained from {@code trade-events}");
 * this service takes the first, because the Trade Executor already computes and
 * persists the correct weighted average cost under transactional guarantees this
 * service would otherwise have to duplicate.
 */
@Entity
@Table(name = "positions")
@IdClass(PositionId.class)
public class PositionEntity {

    @Id
    @Column(name = "account_id")
    private Long accountId;

    @Id
    private String symbol;

    private Integer quantity;

    @Column(name = "average_cost")
    private BigDecimal averageCost;

    public Long getAccountId() {
        return accountId;
    }

    public String getSymbol() {
        return symbol;
    }

    public Integer getQuantity() {
        return quantity;
    }

    public BigDecimal getAverageCost() {
        return averageCost;
    }
}

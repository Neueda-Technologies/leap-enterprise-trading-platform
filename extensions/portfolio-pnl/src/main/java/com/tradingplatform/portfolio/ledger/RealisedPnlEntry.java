package com.tradingplatform.portfolio.ledger;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

/**
 * One booked realised profit-and-loss fact, owned by this extension. Maps
 * {@code portfolio_realised_pnl}, created by
 * src/main/resources/db/portfolio-schema.sql.
 *
 * <p>{@code eventId} is the primary key, which is what makes processing a
 * {@code trade-events} SELL fill idempotent: a replayed event is a duplicate insert on
 * the primary key, not a double booking.
 */
@Entity
@Table(name = "portfolio_realised_pnl")
public class RealisedPnlEntry {

    @Id
    @Column(name = "event_id")
    private UUID eventId;

    @Column(name = "order_id")
    private UUID orderId;

    @Column(name = "account_id")
    private Long accountId;

    private String symbol;

    private Integer quantity;

    @Column(name = "executed_price")
    private BigDecimal executedPrice;

    @Column(name = "average_cost_at_sale")
    private BigDecimal averageCostAtSale;

    @Column(name = "realised_pnl")
    private BigDecimal realisedPnl;

    @Column(name = "executed_on")
    private Instant executedOn;

    protected RealisedPnlEntry() {
        // JPA
    }

    public RealisedPnlEntry(
            UUID eventId,
            UUID orderId,
            Long accountId,
            String symbol,
            Integer quantity,
            BigDecimal executedPrice,
            BigDecimal averageCostAtSale,
            BigDecimal realisedPnl,
            Instant executedOn) {
        this.eventId = eventId;
        this.orderId = orderId;
        this.accountId = accountId;
        this.symbol = symbol;
        this.quantity = quantity;
        this.executedPrice = executedPrice;
        this.averageCostAtSale = averageCostAtSale;
        this.realisedPnl = realisedPnl;
        this.executedOn = executedOn;
    }

    public UUID getEventId() {
        return eventId;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public Long getAccountId() {
        return accountId;
    }

    public String getSymbol() {
        return symbol;
    }

    public Integer getQuantity() {
        return quantity;
    }

    public BigDecimal getExecutedPrice() {
        return executedPrice;
    }

    public BigDecimal getAverageCostAtSale() {
        return averageCostAtSale;
    }

    public BigDecimal getRealisedPnl() {
        return realisedPnl;
    }

    public Instant getExecutedOn() {
        return executedOn;
    }
}

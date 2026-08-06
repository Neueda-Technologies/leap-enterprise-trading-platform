package com.tradingplatform.domain.model;

import com.tradingplatform.domain.exception.OrderNotCancellableException;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

/**
 * An instruction to trade, in any status.
 *
 * <p>An order is a record of intent, written before the trade has happened. That is why a rejected
 * order is still stored: the {@code orders} table is the audit trail, nothing is deleted from it,
 * and a row is only ever moved from {@code NEW} to a terminal status.
 *
 * <p>Two prices live here and they are not the same thing. {@link #getPrice()} is the limit price the
 * customer submitted. {@link #getExecutedPrice()} is the price the Trade Executor achieved against a
 * live quote, and it is null until the order reaches {@code FILLED}. Once execution is asynchronous
 * the two routinely differ, and a report that treats the limit price as the traded price is wrong.
 */
public class Order {

    private final UUID id;
    private final Long accountId;
    private final String symbol;
    private final OrderSide side;
    private final int quantity;
    private final BigDecimal price;
    private final String idempotencyKey;
    private final Instant createdOn;

    private OrderStatus status;
    private BigDecimal executedPrice;
    private Instant executedOn;
    private String rejectReason;

    /**
     * Full constructor, used when rebuilding an order from storage. Use {@link #accept} to create a
     * new one, so that the working status cannot be set to anything but {@code NEW} by mistake.
     */
    public Order(UUID id,
                 Long accountId,
                 String symbol,
                 OrderSide side,
                 int quantity,
                 BigDecimal price,
                 OrderStatus status,
                 String idempotencyKey,
                 Instant createdOn,
                 BigDecimal executedPrice,
                 Instant executedOn,
                 String rejectReason) {
        this.id = Objects.requireNonNull(id, "id");
        this.accountId = Objects.requireNonNull(accountId, "accountId");
        this.symbol = Objects.requireNonNull(symbol, "symbol");
        this.side = Objects.requireNonNull(side, "side");
        this.quantity = quantity;
        this.price = Money.normalise(Objects.requireNonNull(price, "price"));
        this.status = Objects.requireNonNull(status, "status");
        this.idempotencyKey = Objects.requireNonNull(idempotencyKey, "idempotencyKey");
        this.createdOn = Objects.requireNonNull(createdOn, "createdOn");
        this.executedPrice = executedPrice == null ? null : Money.normalise(executedPrice);
        this.executedOn = executedOn;
        this.rejectReason = rejectReason;
    }

    /**
     * Creates an order that has passed every business rule and is awaiting execution. The status is
     * {@code NEW} and no other value is reachable at creation.
     */
    public static Order accept(UUID id,
                               Long accountId,
                               String symbol,
                               OrderSide side,
                               int quantity,
                               BigDecimal price,
                               String idempotencyKey,
                               Instant createdOn) {
        return new Order(id, accountId, symbol, side, quantity, price, OrderStatus.NEW,
                idempotencyKey, createdOn, null, null, null);
    }

    /**
     * Cash the order would move at its limit price: {@code quantity * price}. Business rule 6
     * compares this against the cash balance.
     */
    public BigDecimal notionalValue() {
        return Money.consideration(quantity, price);
    }

    /** Cash the order actually moves at a given execution price. */
    public BigDecimal considerationAt(BigDecimal executionPrice) {
        return Money.consideration(quantity, executionPrice);
    }

    /** True while the order is still working, which is the only state it can be cancelled from. */
    public boolean isCancellable() {
        return status == OrderStatus.NEW;
    }

    /**
     * Moves the order to {@code FILLED}.
     *
     * @throws IllegalStateException when the order is already terminal. Reaching this is a
     *                               programming error rather than a business rule failure: the
     *                               guarded update in the persistence layer is what stops two
     *                               executor instances filling the same order, and it should have
     *                               reported zero rows affected long before this method was called.
     */
    public void fill(BigDecimal filledAt, Instant filledOn) {
        requireWorking("fill");
        this.executedPrice = Money.normalise(Objects.requireNonNull(filledAt, "executedPrice"));
        this.executedOn = Objects.requireNonNull(filledOn, "executedOn");
        this.status = OrderStatus.FILLED;
    }

    /**
     * Moves the order to {@code REJECTED} with a machine-readable reason, for example
     * {@code INSUFFICIENT_FUNDS} or {@code PRICE_NOT_MET}. The reason mirrors the {@code reason}
     * field on the {@code trade-events} message.
     */
    public void reject(String reason, Instant rejectedOn) {
        requireWorking("reject");
        this.rejectReason = Objects.requireNonNull(reason, "rejectReason");
        this.executedOn = rejectedOn;
        this.status = OrderStatus.REJECTED;
    }

    /**
     * Moves the order to {@code CANCELLED}.
     *
     * @throws OrderNotCancellableException when the order is already terminal. This one is a
     *                                      business rule failure, because a customer cancelling an
     *                                      order that has just filled is a normal race, not a bug.
     */
    public void cancel() {
        if (!isCancellable()) {
            throw new OrderNotCancellableException(id, status);
        }
        this.status = OrderStatus.CANCELLED;
    }

    private void requireWorking(String transition) {
        if (status != OrderStatus.NEW) {
            throw new IllegalStateException(
                    "Cannot " + transition + " an order in status " + status);
        }
    }

    public UUID getId() {
        return id;
    }

    /** The numeric account key, {@code accounts.id}. */
    public Long getAccountId() {
        return accountId;
    }

    public String getSymbol() {
        return symbol;
    }

    public OrderSide getSide() {
        return side;
    }

    public int getQuantity() {
        return quantity;
    }

    /** The limit price submitted by the customer. */
    public BigDecimal getPrice() {
        return price;
    }

    public OrderStatus getStatus() {
        return status;
    }

    public String getIdempotencyKey() {
        return idempotencyKey;
    }

    public Instant getCreatedOn() {
        return createdOn;
    }

    /** The price the fill was achieved at. Null until the order is {@code FILLED}. */
    public BigDecimal getExecutedPrice() {
        return executedPrice;
    }

    /** When the order reached a terminal status. */
    public Instant getExecutedOn() {
        return executedOn;
    }

    /** Machine-readable cause on a {@code REJECTED} order. Null otherwise. */
    public String getRejectReason() {
        return rejectReason;
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        return other instanceof Order order && id.equals(order.id);
    }

    @Override
    public int hashCode() {
        return id.hashCode();
    }

    @Override
    public String toString() {
        return "Order[id=" + id + ", side=" + side + ", symbol=" + symbol
                + ", quantity=" + quantity + ", status=" + status + "]";
    }
}

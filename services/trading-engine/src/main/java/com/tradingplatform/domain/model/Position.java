package com.tradingplatform.domain.model;

import com.tradingplatform.domain.exception.InsufficientHoldingsException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Objects;

/**
 * The net holding of one instrument in one account.
 *
 * <p>Derived state. Every position in the platform can be rebuilt from the order history, and a team
 * should prove that it can, because a position table that has drifted from the trades that produced
 * it is the failure mode that costs a trading desk money.
 *
 * <p>The average cost rule is asymmetric, and the asymmetry is the point. A buy recalculates it as
 * {@code (oldQty * oldAvg + newQty * fillPrice) / (oldQty + newQty)}. A sell reduces the quantity and
 * leaves the average cost alone. Keeping the cost basis intact through a sale is what makes realised
 * profit and loss computable at the point of sale, and it is what the Sprint 10 Portfolio extension
 * depends on.
 */
public class Position {

    /**
     * Working precision for the average cost calculation. The division is performed here and rounded
     * to the platform money scale once, at the end. Rounding the intermediate would push the error
     * into every later trade.
     */
    private static final int DIVISION_SCALE = 10;

    private final Long accountId;
    private final String symbol;
    private int quantity;
    private BigDecimal averageCost;

    public Position(Long accountId, String symbol, int quantity, BigDecimal averageCost) {
        this.accountId = Objects.requireNonNull(accountId, "accountId");
        this.symbol = Objects.requireNonNull(symbol, "symbol");
        if (quantity < 0) {
            throw new IllegalArgumentException("A position quantity cannot be negative");
        }
        this.quantity = quantity;
        this.averageCost = Money.normalise(Objects.requireNonNull(averageCost, "averageCost"));
    }

    /**
     * A position that does not exist yet. Used rather than a null so that the placement and
     * settlement rules never branch on nullness, only on quantity.
     */
    public static Position empty(Long accountId, String symbol) {
        return new Position(accountId, symbol, 0, Money.ZERO);
    }

    /**
     * True when the holding covers a sell of this size. This is business rule 7 stated as a question.
     */
    public boolean canCover(int sellQuantity) {
        return quantity >= sellQuantity;
    }

    /**
     * Applies a fill to the holding.
     *
     * <p>A buy increases the quantity and recalculates the weighted average cost. A sell decreases
     * the quantity and leaves the average cost unchanged.
     *
     * @param side       direction of the fill
     * @param filled     quantity filled, greater than zero
     * @param filledAt   price the fill was achieved at, used only by a buy
     * @throws IllegalArgumentException     when the quantity is not greater than zero
     * @throws InsufficientHoldingsException when a sell exceeds the holding. Checked before any
     *                                       field is written, so a refused sell leaves the position
     *                                       exactly as it was.
     */
    public void apply(OrderSide side, int filled, BigDecimal filledAt) {
        Objects.requireNonNull(side, "side");
        Objects.requireNonNull(filledAt, "filledAt");
        if (filled <= 0) {
            throw new IllegalArgumentException("A fill quantity must be greater than zero");
        }

        if (side == OrderSide.BUY) {
            applyBuy(filled, filledAt);
        } else {
            applySell(filled);
        }
    }

    private void applyBuy(int filled, BigDecimal filledAt) {
        BigDecimal existingCost = averageCost.multiply(BigDecimal.valueOf(quantity));
        BigDecimal addedCost = filledAt.multiply(BigDecimal.valueOf(filled));
        int newQuantity = quantity + filled;

        this.averageCost = existingCost.add(addedCost)
                .divide(BigDecimal.valueOf(newQuantity), DIVISION_SCALE, RoundingMode.HALF_UP)
                .setScale(Money.SCALE, Money.ROUNDING);
        this.quantity = newQuantity;
    }

    private void applySell(int filled) {
        if (!canCover(filled)) {
            throw new InsufficientHoldingsException(symbol, filled, quantity);
        }
        this.quantity = quantity - filled;
        // The average cost is deliberately not touched. See the class javadoc.
    }

    /**
     * Value of the holding at a given price: {@code quantity * price}.
     *
     * <p>The price is a parameter because the domain has no market data. Fetching a quote is I/O, the
     * engine performs none, and a valuation that silently used a stale cached price would be worse
     * than no valuation. The Trade REST API does not call this; the Sprint 10 Portfolio and P&L
     * extension does, with a live Fauxnance quote.
     */
    public BigDecimal marketValue(BigDecimal price) {
        Objects.requireNonNull(price, "price");
        return Money.consideration(quantity, price);
    }

    /**
     * Cost basis of the holding: {@code quantity * averageCost}. Subtract it from the market value to
     * get unrealised profit and loss.
     */
    public BigDecimal costBasis() {
        return Money.consideration(quantity, averageCost);
    }

    /** True when nothing is held. The API does not return positions in this state. */
    public boolean isEmpty() {
        return quantity == 0;
    }

    /** The numeric account key, {@code accounts.id}. */
    public Long getAccountId() {
        return accountId;
    }

    public String getSymbol() {
        return symbol;
    }

    /** Net held quantity. Never negative; short selling is out of scope. */
    public int getQuantity() {
        return quantity;
    }

    /** Weighted average cost per unit. */
    public BigDecimal getAverageCost() {
        return averageCost;
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        return other instanceof Position position
                && accountId.equals(position.accountId)
                && symbol.equals(position.symbol);
    }

    @Override
    public int hashCode() {
        return Objects.hash(accountId, symbol);
    }

    @Override
    public String toString() {
        return "Position[accountId=" + accountId + ", symbol=" + symbol + ", quantity=" + quantity + "]";
    }
}

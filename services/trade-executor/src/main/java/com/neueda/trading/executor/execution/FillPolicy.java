package com.neueda.trading.executor.execution;

import com.neueda.trading.executor.domain.Side;
import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * The fill rules, with no I/O and no framework. Everything the platform decides about a price is
 * decided here, so the rules can be tested by themselves and argued about in a review.
 *
 * <p><strong>Marketability.</strong> A BUY is marketable when the quote is at or below the limit
 * price. A SELL is marketable when the quote is at or above it. An order that is not marketable is
 * rejected with {@code PRICE_NOT_MET} rather than held: the order status enumeration has no working
 * state between NEW and terminal, so there is nowhere to park a resting order.
 *
 * <p><strong>Fill price.</strong> A BUY fills at the lower of the limit price and the quote, a SELL
 * at the higher. Under the marketability gate those reduce to the quote, which is the intended
 * behaviour: the customer gets the market price, not the price they were willing to accept. The
 * min and max form is kept because it is the invariant that matters, and it still holds if a later
 * sprint adds market orders or relaxes the gate. A customer must never pay more than their limit or
 * receive less than it.
 *
 * <p><strong>Rounding.</strong> Fauxnance returns more precision than {@code NUMERIC(18,2)} holds.
 * The quote is rounded to two decimal places, half up, before it is compared or stored, so the
 * price on the order row, the price on the event and the price the arithmetic used are the same
 * number. Rounding after the comparison would let an order fill at a price that failed its own
 * limit check.
 */
public final class FillPolicy {

    public static final int MONEY_SCALE = 2;
    public static final RoundingMode MONEY_ROUNDING = RoundingMode.HALF_UP;
    public static final BigDecimal ZERO_MONEY = money(BigDecimal.ZERO);

    private FillPolicy() {
    }

    /** Rounds a value to the platform's money scale. */
    public static BigDecimal money(BigDecimal value) {
        return value.setScale(MONEY_SCALE, MONEY_ROUNDING);
    }

    public static boolean isMarketable(Side side, BigDecimal limitPrice, BigDecimal quotePrice) {
        BigDecimal limit = money(limitPrice);
        BigDecimal quote = money(quotePrice);
        return side == Side.BUY ? quote.compareTo(limit) <= 0 : quote.compareTo(limit) >= 0;
    }

    public static BigDecimal fillPrice(Side side, BigDecimal limitPrice, BigDecimal quotePrice) {
        BigDecimal limit = money(limitPrice);
        BigDecimal quote = money(quotePrice);
        return side == Side.BUY ? limit.min(quote) : limit.max(quote);
    }

    /** Quantity multiplied by price, at the money scale. Negative for a buy is applied by the caller. */
    public static BigDecimal notional(int quantity, BigDecimal price) {
        return money(price.multiply(BigDecimal.valueOf(quantity)));
    }

    /**
     * Weighted average cost after a buy: {@code (oldQty * oldAvg + fillQty * fillPrice) /
     * (oldQty + fillQty)}. A sell does not call this. Reducing a holding leaves the average cost
     * where it is, which is what makes realised profit and loss computable at the point of sale.
     */
    public static BigDecimal averageCostAfterBuy(int heldQuantity, BigDecimal heldAverageCost,
                                                 int fillQuantity, BigDecimal fillPrice) {
        int total = heldQuantity + fillQuantity;
        if (total <= 0) {
            return ZERO_MONEY;
        }
        BigDecimal heldValue = heldAverageCost.multiply(BigDecimal.valueOf(heldQuantity));
        BigDecimal filledValue = fillPrice.multiply(BigDecimal.valueOf(fillQuantity));
        return heldValue.add(filledValue)
                .divide(BigDecimal.valueOf(total), MONEY_SCALE, MONEY_ROUNDING);
    }
}

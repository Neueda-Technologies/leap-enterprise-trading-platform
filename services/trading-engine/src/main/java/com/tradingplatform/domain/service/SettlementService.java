package com.tradingplatform.domain.service;

import com.tradingplatform.domain.exception.AccountNotActiveException;
import com.tradingplatform.domain.exception.InsufficientFundsException;
import com.tradingplatform.domain.exception.InsufficientHoldingsException;
import com.tradingplatform.domain.model.Account;
import com.tradingplatform.domain.model.Money;
import com.tradingplatform.domain.model.Order;
import com.tradingplatform.domain.model.OrderSide;
import com.tradingplatform.domain.model.OrderStatus;
import com.tradingplatform.domain.model.Position;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Objects;

/**
 * Business rules 9 and 10: cash and position move together, and every outcome is recorded.
 *
 * <p>Atomicity is a database property, but it starts here. The service checks every precondition
 * before it writes the first field. A settlement that is going to fail therefore fails with the
 * account balance, the position and the order status exactly as they were, so the caller's
 * transaction has nothing to roll back that the domain has already half applied. Building it the
 * other way, debiting the account and then discovering the holding is short, produces an object
 * graph whose correctness depends on someone else remembering to roll back.
 *
 * <p>In Sprint 6 the Trade REST API calls this in process, immediately after recording the order,
 * and the order comes back {@code FILLED}. From Sprint 7 the Trade Executor calls it instead, after
 * pricing the order against a live Fauxnance quote, and the API returns {@code NEW}. The rules do not
 * change between the two; only the caller does. That is the reason they live in a library with no
 * I/O.
 *
 * <p>Rejection is not failure. {@link #reject} exists because a rejected order is an event and an
 * audit record, not something to discard. A consumer that only ever sees fills reports a fill rate of
 * 100 per cent.
 */
public class SettlementService {

    /**
     * Applies a fill to the account and the position, and moves the order to {@code FILLED}.
     *
     * @param order         the working order, in status {@code NEW}
     * @param account       the account to debit or credit
     * @param position      the current holding, or null when the account holds none
     * @param executedPrice the price achieved, which is the limit price in Sprint 6 and a live quote
     *                      from Sprint 7
     * @param executedOn    when the fill happened
     * @return what moved, ready to serialise onto {@code trade-events}
     * @throws AccountNotActiveException     if the account stopped being ACTIVE between placement
     *                                       and settlement, which is possible once the two are
     *                                       separated by a queue
     * @throws InsufficientFundsException    if the cash no longer covers the consideration
     * @throws InsufficientHoldingsException if the holding no longer covers the sell
     */
    public Settlement settle(Order order,
                             Account account,
                             Position position,
                             BigDecimal executedPrice,
                             Instant executedOn) {
        Objects.requireNonNull(order, "order");
        Objects.requireNonNull(account, "account");
        Objects.requireNonNull(executedPrice, "executedPrice");
        Objects.requireNonNull(executedOn, "executedOn");

        if (order.getStatus() != OrderStatus.NEW) {
            throw new IllegalStateException("Cannot settle an order in status " + order.getStatus());
        }
        if (!Money.isPositive(executedPrice)) {
            throw new IllegalArgumentException("An execution price must be greater than zero");
        }

        Position holding = position == null
                ? Position.empty(account.getId(), order.getSymbol())
                : position;
        BigDecimal consideration = order.considerationAt(executedPrice);

        // Every check first. Nothing below this line may fail.
        checkPreconditions(order, account, holding, consideration);

        BigDecimal cashDelta;
        if (order.getSide() == OrderSide.BUY) {
            account.debit(consideration);
            cashDelta = consideration.negate();
        } else {
            account.credit(consideration);
            cashDelta = consideration;
        }
        holding.apply(order.getSide(), order.getQuantity(), executedPrice);
        order.fill(executedPrice, executedOn);

        return new Settlement(
                order.getId(),
                account.getId(),
                order.getSymbol(),
                order.getSide(),
                order.getQuantity(),
                order.getPrice(),
                executedPrice,
                OrderStatus.FILLED,
                cashDelta,
                holding.getQuantity(),
                holding.getAverageCost(),
                executedOn);
    }

    /**
     * Moves the order to {@code REJECTED} without touching cash or the position, and reports it in
     * the same shape as a fill so that one publisher handles both.
     *
     * @param reason machine-readable cause, for example {@code INSUFFICIENT_FUNDS} or
     *               {@code PRICE_NOT_MET}
     */
    public Settlement reject(Order order, Position position, String reason, Instant rejectedOn) {
        Objects.requireNonNull(order, "order");
        Objects.requireNonNull(reason, "reason");
        Objects.requireNonNull(rejectedOn, "rejectedOn");

        order.reject(reason, rejectedOn);

        int quantityAfter = position == null ? 0 : position.getQuantity();
        BigDecimal averageCostAfter = position == null ? Money.ZERO : position.getAverageCost();

        return new Settlement(
                order.getId(),
                order.getAccountId(),
                order.getSymbol(),
                order.getSide(),
                order.getQuantity(),
                order.getPrice(),
                null,
                OrderStatus.REJECTED,
                Money.ZERO,
                quantityAfter,
                averageCostAfter,
                rejectedOn);
    }

    /**
     * Moves the order to {@code CANCELLED} and reports it in the same shape. Cash and position do not
     * move, because a cancelled order never executed.
     */
    public Settlement cancel(Order order, Position position, Instant cancelledOn) {
        Objects.requireNonNull(order, "order");
        Objects.requireNonNull(cancelledOn, "cancelledOn");

        order.cancel();

        int quantityAfter = position == null ? 0 : position.getQuantity();
        BigDecimal averageCostAfter = position == null ? Money.ZERO : position.getAverageCost();

        return new Settlement(
                order.getId(),
                order.getAccountId(),
                order.getSymbol(),
                order.getSide(),
                order.getQuantity(),
                order.getPrice(),
                null,
                OrderStatus.CANCELLED,
                Money.ZERO,
                quantityAfter,
                averageCostAfter,
                cancelledOn);
    }

    private static void checkPreconditions(Order order,
                                           Account account,
                                           Position holding,
                                           BigDecimal consideration) {
        if (!account.isActive()) {
            throw new AccountNotActiveException(account.getId(), account.getStatus());
        }
        if (order.getSide() == OrderSide.BUY && !account.canAfford(consideration)) {
            throw new InsufficientFundsException(consideration, account.getCashBalance());
        }
        if (order.getSide() == OrderSide.SELL && !holding.canCover(order.getQuantity())) {
            throw new InsufficientHoldingsException(
                    order.getSymbol(), order.getQuantity(), holding.getQuantity());
        }
    }
}

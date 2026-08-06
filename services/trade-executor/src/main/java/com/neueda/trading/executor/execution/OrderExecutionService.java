package com.neueda.trading.executor.execution;

import com.neueda.trading.executor.config.ExecutorProperties;
import com.neueda.trading.executor.domain.OrderStatus;
import com.neueda.trading.executor.domain.RejectReason;
import com.neueda.trading.executor.domain.Side;
import com.neueda.trading.executor.messaging.NonRetryableMessageException;
import com.neueda.trading.executor.messaging.OrderPlacedPayload;
import com.neueda.trading.executor.messaging.TradeEventEnvelope;
import com.neueda.trading.executor.messaging.TradeEventPayload;
import com.neueda.trading.executor.persistence.AccountRow;
import com.neueda.trading.executor.persistence.ExecutionRepository;
import com.neueda.trading.executor.persistence.OptimisticLockConflictException;
import com.neueda.trading.executor.persistence.OrderRow;
import com.neueda.trading.executor.persistence.PositionRow;
import com.neueda.trading.executor.quote.Quote;
import com.neueda.trading.executor.quote.QuoteClient;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * The execution venue.
 *
 * <p>The sequence is fixed and the order of the steps carries the guarantees.
 *
 * <ol>
 *   <li>Load the order. A status other than NEW means a previous delivery already settled it, so
 *       the message is dropped and nothing is published. That is the idempotency check the Sprint 7
 *       acceptance criterion asks a team to demonstrate.</li>
 *   <li>Pause for the simulated execution latency.</li>
 *   <li>Check tradability and fetch a quote. Both are outside the transaction, because an HTTP call
 *       inside a database transaction holds a connection open for the length of the network round
 *       trip.</li>
 *   <li>Settle inside one transaction: re-read the account and the position, apply the rules,
 *       perform the guarded status transition, move the cash under the optimistic lock, and write
 *       the position.</li>
 *   <li>Publish the outcome after the commit. The caller does that; this class returns the event.</li>
 * </ol>
 *
 * <p>The guarded transition runs before the cash movement inside the transaction. A duplicate
 * delivery therefore fails the transition and returns before any money moves, and the failure is a
 * zero row count rather than an exception.
 */
@Service
public class OrderExecutionService {

    private static final Logger log = LoggerFactory.getLogger(OrderExecutionService.class);

    private final ExecutionRepository repository;
    private final QuoteClient quoteClient;
    private final TransactionTemplate transactionTemplate;
    private final ExecutionLatency latency;
    private final ExecutorProperties properties;
    private final Clock clock;

    public OrderExecutionService(ExecutionRepository repository,
                                 QuoteClient quoteClient,
                                 TransactionTemplate transactionTemplate,
                                 ExecutionLatency latency,
                                 ExecutorProperties properties,
                                 Clock clock) {
        this.repository = repository;
        this.quoteClient = quoteClient;
        this.transactionTemplate = transactionTemplate;
        this.latency = latency;
        this.properties = properties;
        this.clock = clock;
    }

    /**
     * @return the event to publish, or empty when this delivery changed nothing because the order
     *         was already in a terminal state
     */
    public Optional<TradeEventEnvelope> execute(OrderPlacedPayload message) {
        message.validate();

        OrderRow order = repository.findOrder(message.orderId())
                .orElseThrow(() -> new NonRetryableMessageException(
                        "No order " + message.orderId() + " exists. The producer publishes after "
                                + "the commit, so an unknown order identifier is a poison message."));

        if (order.status() != OrderStatus.NEW) {
            log.info("Order {} is already {}. Skipping duplicate delivery.",
                    order.id(), order.status());
            return Optional.empty();
        }

        latency.pause();

        Pricing pricing = price(order);
        return settleWithRetry(order, pricing);
    }

    /**
     * Everything that can be decided before the transaction opens: whether the instrument is still
     * tradable, whether a price exists, and whether that price is inside the limit.
     */
    private Pricing price(OrderRow order) {
        if (!repository.isTradable(order.symbol())) {
            log.info("Order {} rejected: {} is not tradable", order.id(), order.symbol());
            return Pricing.rejected(RejectReason.INSTRUMENT_NOT_TRADABLE);
        }

        Optional<Quote> quote = quoteClient.quoteFor(order.symbol());
        if (quote.isEmpty()) {
            log.warn("Order {} rejected: no Fauxnance quote for {}", order.id(), order.symbol());
            return Pricing.rejected(RejectReason.PRICING_UNAVAILABLE);
        }

        Quote observed = quote.get();
        if (observed.stale()) {
            log.warn("Quote for {} is flagged stale, observed at {}. Pricing the fill against it "
                    + "anyway; the staleness is recorded on the market-data topic.",
                    observed.symbol(), observed.asOf());
        }

        BigDecimal quotePrice = FillPolicy.money(observed.price());
        if (!FillPolicy.isMarketable(order.side(), order.price(), quotePrice)) {
            log.info("Order {} rejected: {} {} limit {} against quote {}",
                    order.id(), order.side(), order.symbol(), order.price(), quotePrice);
            return Pricing.rejected(RejectReason.PRICE_NOT_MET);
        }
        return Pricing.marketable(quotePrice);
    }

    private Optional<TradeEventEnvelope> settleWithRetry(OrderRow order, Pricing pricing) {
        int maxAttempts = Math.max(1, properties.getOptimisticLock().getMaxAttempts());
        for (int attempt = 1; attempt <= maxAttempts; attempt++) {
            try {
                return Optional.ofNullable(
                        transactionTemplate.execute(status -> settle(order, pricing)));
            } catch (OptimisticLockConflictException e) {
                log.info("Attempt {} of {} for order {} lost the optimistic lock: {}",
                        attempt, maxAttempts, order.id(), e.getMessage());
                if (attempt == maxAttempts) {
                    throw e;
                }
                backoff();
            }
        }
        throw new IllegalStateException("Unreachable retry state for order " + order.id());
    }

    /**
     * Runs inside the transaction. Returns null when the guarded transition affected no rows, which
     * means a concurrent delivery settled the order first.
     */
    private TradeEventEnvelope settle(OrderRow order, Pricing pricing) {
        AccountRow account = repository.findAccount(order.accountId())
                .orElseThrow(() -> new NonRetryableMessageException(
                        "Order " + order.id() + " references account " + order.accountId()
                                + ", which does not exist"));
        PositionRow position = repository.findPosition(order.accountId(), order.symbol());
        Instant now = clock.instant().truncatedTo(ChronoUnit.SECONDS);

        RejectReason reason = pricing.rejection();
        if (reason == null && !account.isActive()) {
            reason = RejectReason.ACCOUNT_NOT_ACTIVE;
        }

        BigDecimal fillPrice = null;
        BigDecimal notional = null;
        if (reason == null) {
            fillPrice = FillPolicy.fillPrice(order.side(), order.price(), pricing.quotePrice());
            notional = FillPolicy.notional(order.quantity(), fillPrice);
            reason = affordability(order, account, position, notional);
        }

        if (reason != null) {
            return reject(order, position, reason, now);
        }
        return fill(order, account, position, fillPrice, notional, now);
    }

    /**
     * Rules 6 and 7, re-checked at execution time. The Trade REST API already checked them at
     * acceptance, against the limit price and against the balance as it was then. Both can have
     * moved: another order on the same account may have spent the cash or sold the holding, and the
     * fill price is not the limit price.
     */
    private RejectReason affordability(OrderRow order, AccountRow account, PositionRow position,
                                       BigDecimal notional) {
        if (order.side() == Side.BUY) {
            return account.cashBalance().compareTo(notional) < 0
                    ? RejectReason.INSUFFICIENT_FUNDS
                    : null;
        }
        return position.quantity() < order.quantity()
                ? RejectReason.INSUFFICIENT_HOLDINGS
                : null;
    }

    private TradeEventEnvelope reject(OrderRow order, PositionRow position, RejectReason reason,
                                      Instant now) {
        if (repository.markRejected(order.id(), reason.name(), now) == 0) {
            log.info("Order {} was settled by another delivery before this one could reject it",
                    order.id());
            return null;
        }
        log.info("Order {} REJECTED: {}", order.id(), reason);
        TradeEventPayload payload = new TradeEventPayload(
                order.id().toString(),
                order.accountId(),
                order.symbol(),
                order.side(),
                order.quantity(),
                FillPolicy.money(order.price()),
                null,
                OrderStatus.REJECTED,
                reason.name(),
                FillPolicy.ZERO_MONEY,
                position.quantity(),
                FillPolicy.money(position.averageCost()),
                iso(now));
        return envelope(TradeEventEnvelope.ORDER_REJECTED, payload, now);
    }

    private TradeEventEnvelope fill(OrderRow order, AccountRow account, PositionRow position,
                                    BigDecimal fillPrice, BigDecimal notional, Instant now) {
        if (repository.markFilled(order.id(), fillPrice, now) == 0) {
            log.info("Order {} was settled by another delivery before this one could fill it",
                    order.id());
            return null;
        }

        boolean buy = order.side() == Side.BUY;
        BigDecimal cashDelta = buy ? notional.negate() : notional;
        repository.updateCashBalance(order.accountId(),
                account.cashBalance().add(cashDelta), account.version(), now);

        int quantityAfter = buy
                ? position.quantity() + order.quantity()
                : position.quantity() - order.quantity();
        BigDecimal averageCostAfter;
        if (buy) {
            averageCostAfter = FillPolicy.averageCostAfterBuy(
                    position.quantity(), position.averageCost(), order.quantity(), fillPrice);
        } else if (quantityAfter == 0) {
            // The holding is closed. The application role has no DELETE grant, so the row stays at
            // zero. Resetting the average cost keeps the next buy's weighted average correct and
            // satisfies the non-negative check.
            averageCostAfter = FillPolicy.ZERO_MONEY;
        } else {
            averageCostAfter = FillPolicy.money(position.averageCost());
        }
        repository.upsertPosition(order.accountId(), order.symbol(), quantityAfter,
                averageCostAfter);

        log.info("Order {} FILLED: {} {} {} at {}, cash delta {}",
                order.id(), order.side(), order.quantity(), order.symbol(), fillPrice, cashDelta);

        TradeEventPayload payload = new TradeEventPayload(
                order.id().toString(),
                order.accountId(),
                order.symbol(),
                order.side(),
                order.quantity(),
                FillPolicy.money(order.price()),
                fillPrice,
                OrderStatus.FILLED,
                null,
                cashDelta,
                quantityAfter,
                averageCostAfter,
                iso(now));
        return envelope(TradeEventEnvelope.ORDER_FILLED, payload, now);
    }

    private TradeEventEnvelope envelope(String eventType, TradeEventPayload payload, Instant now) {
        return new TradeEventEnvelope(
                UUID.randomUUID().toString(),
                eventType,
                iso(now),
                TradeEventEnvelope.SOURCE,
                TradeEventEnvelope.SCHEMA_VERSION,
                payload);
    }

    private static String iso(Instant instant) {
        return DateTimeFormatter.ISO_INSTANT.format(instant);
    }

    private void backoff() {
        try {
            Thread.sleep(properties.getOptimisticLock().getBackoff().toMillis());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while backing off an optimistic lock retry", e);
        }
    }

    /**
     * The outcome of everything decided before the transaction. Either a rejection reason or a
     * usable quote price, never both and never neither.
     */
    private record Pricing(RejectReason rejection, BigDecimal quotePrice) {

        static Pricing rejected(RejectReason reason) {
            return new Pricing(reason, null);
        }

        static Pricing marketable(BigDecimal quotePrice) {
            return new Pricing(null, quotePrice);
        }
    }
}

package com.tradingplatform.tradeapi.service;

import com.tradingplatform.domain.dto.PlaceOrderRequest;
import com.tradingplatform.domain.exception.AccountNotActiveException;
import com.tradingplatform.domain.exception.AccountNotFoundException;
import com.tradingplatform.domain.exception.DuplicateOrderException;
import com.tradingplatform.domain.exception.OrderNotCancellableException;
import com.tradingplatform.domain.exception.OrderNotFoundException;
import com.tradingplatform.domain.model.Account;
import com.tradingplatform.domain.model.Instrument;
import com.tradingplatform.domain.model.Order;
import com.tradingplatform.domain.model.Position;
import com.tradingplatform.domain.service.OrderPlacementService;
import com.tradingplatform.domain.service.Settlement;
import com.tradingplatform.domain.service.SettlementService;
import com.tradingplatform.tradeapi.config.ExecutionMode;
import com.tradingplatform.tradeapi.config.TradingProperties;
import com.tradingplatform.tradeapi.messaging.OrderPlacedPayload;
import com.tradingplatform.tradeapi.messaging.TradeEventPayload;
import com.tradingplatform.tradeapi.repository.AccountMapper;
import com.tradingplatform.tradeapi.repository.InstrumentMapper;
import com.tradingplatform.tradeapi.repository.OrderMapper;
import com.tradingplatform.tradeapi.repository.PositionMapper;
import com.tradingplatform.tradeapi.security.AccountAccessDeniedException;
import com.tradingplatform.tradeapi.security.AuthenticatedUser;
import com.tradingplatform.tradeapi.web.dto.OrderResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.util.UUID;

/**
 * Placing and cancelling orders.
 *
 * <p>This class orchestrates. It authorises the caller, loads what the rules need, calls the domain,
 * writes the result and announces it. It contains no business rule of its own: every decision about
 * whether a trade may happen is made in {@link OrderPlacementService} or {@link SettlementService},
 * where it can be tested with plain objects.
 *
 * <p>Both public methods are {@code @Transactional}. The order row, the cash balance and the position
 * either all move or none of them do. Splitting them across transactions produces an account that has
 * been debited for an order that does not exist, and no amount of retrying fixes it.
 *
 * <p>Events are published through {@link ApplicationEventPublisher} rather than sent to Kafka here.
 * The Kafka publisher listens {@code AFTER_COMMIT}, so an order that is rolled back is never
 * announced. It also means this class can be unit tested without a broker.
 */
@Service
public class OrderService {

    private static final Logger log = LoggerFactory.getLogger(OrderService.class);

    private static final String MESSAGE_ACCEPTED = "Order accepted";
    private static final String MESSAGE_EXECUTED = "Order executed";
    private static final String MESSAGE_CANCELLED = "Order cancelled";

    private final AccountMapper accountMapper;
    private final InstrumentMapper instrumentMapper;
    private final OrderMapper orderMapper;
    private final PositionMapper positionMapper;
    private final OrderPlacementService placementService;
    private final SettlementService settlementService;
    private final ApplicationEventPublisher events;
    private final TradingProperties properties;
    private final Clock clock;

    public OrderService(AccountMapper accountMapper,
                        InstrumentMapper instrumentMapper,
                        OrderMapper orderMapper,
                        PositionMapper positionMapper,
                        OrderPlacementService placementService,
                        SettlementService settlementService,
                        ApplicationEventPublisher events,
                        TradingProperties properties,
                        Clock clock) {
        this.accountMapper = accountMapper;
        this.instrumentMapper = instrumentMapper;
        this.orderMapper = orderMapper;
        this.positionMapper = positionMapper;
        this.placementService = placementService;
        this.settlementService = settlementService;
        this.events = events;
        this.properties = properties;
        this.clock = clock;
    }

    /**
     * Validates an order against business rules 1 to 8, records it, and either fills it in process or
     * publishes it for the Trade Executor.
     *
     * @return the order, {@code NEW} in asynchronous mode and terminal in synchronous mode
     */
    @Transactional
    public OrderResponse placeOrder(PlaceOrderRequest request, AuthenticatedUser user) {
        requireAccess(user, request.accountId());

        Instant now = clock.instant();
        Account account = accountMapper.findById(request.accountId());
        Instrument instrument = instrumentMapper.findBySymbol(request.symbol());
        Position position = positionMapper.find(request.accountId(), request.symbol());

        Order order = placementService.placeOrder(
                request, account, instrument, position, UUID.randomUUID(), now);

        record(order);

        if (properties.executionMode() == ExecutionMode.SYNC) {
            return fillInProcess(order, account, position, now);
        }

        events.publishEvent(OrderPlacedPayload.of(order));
        log.info("Order accepted orderId={} accountId={} symbol={} side={} quantity={} mode=ASYNC",
                order.getId(), order.getAccountId(), order.getSymbol(),
                order.getSide(), order.getQuantity());
        return OrderResponse.of(order, MESSAGE_ACCEPTED);
    }

    /**
     * Cancels an order that is still working.
     *
     * <p>Cancellation is a guarded state transition performed by the database, not a status check
     * followed by an update. Between the check and the update the Trade Executor, running in another
     * process, may have filled the order. The guard makes the two mutually exclusive.
     */
    @Transactional
    public OrderResponse cancelOrder(UUID orderId, AuthenticatedUser user) {
        Order order = orderMapper.findById(orderId);
        if (order == null) {
            throw new OrderNotFoundException(orderId);
        }
        requireAccess(user, order.getAccountId());
        requireActiveAccount(order.getAccountId());

        if (orderMapper.cancelIfNew(orderId) != 1) {
            // Zero rows means the order was not NEW when the update ran. Whatever the in-memory copy
            // said a moment ago is not evidence.
            throw new OrderNotCancellableException(orderId, order.getStatus());
        }

        Position position = positionMapper.find(order.getAccountId(), order.getSymbol());
        Settlement settlement = settlementService.cancel(order, position, clock.instant());

        events.publishEvent(TradeEventPayload.of(
                settlement, TradeEventPayload.REASON_CANCELLED_BY_CUSTOMER));

        log.info("Order cancelled orderId={} accountId={}", order.getId(), order.getAccountId());
        return OrderResponse.of(order, MESSAGE_CANCELLED);
    }

    /**
     * Sprint 6 behaviour. Fills the order at its own limit price and moves cash and position in the
     * same transaction that recorded it.
     *
     * <p>There is no live quote here, so the fill price is the limit price. That is the honest
     * simplification: this mode exists because the Trade Executor and the Fauxnance integration do
     * not yet exist, not because filling at the limit is a sensible execution model.
     */
    private OrderResponse fillInProcess(Order order, Account account, Position position, Instant now) {
        int expectedVersion = account.getVersion();
        Position holding = position == null
                ? Position.empty(account.getId(), order.getSymbol())
                : position;

        Settlement settlement =
                settlementService.settle(order, account, holding, order.getPrice(), now);

        if (accountMapper.updateCashBalance(
                account.getId(), account.getCashBalance(), expectedVersion, now) != 1) {
            throw new ConcurrentUpdateException("accounts.version moved during order placement");
        }
        account.writeAccepted(now);

        positionMapper.upsert(holding.getAccountId(), holding.getSymbol(),
                holding.getQuantity(), holding.getAverageCost());

        if (orderMapper.fillIfNew(order.getId(), settlement.executedPrice(), now) != 1) {
            throw new ConcurrentUpdateException("orders.status moved during order placement");
        }

        events.publishEvent(TradeEventPayload.of(settlement, null));

        log.info("Order filled orderId={} accountId={} symbol={} side={} quantity={} mode=SYNC",
                order.getId(), order.getAccountId(), order.getSymbol(),
                order.getSide(), order.getQuantity());
        return OrderResponse.of(order, MESSAGE_EXECUTED);
    }

    /**
     * Business rule 8. The unique constraint is the check; this method only translates its violation
     * into the platform's vocabulary.
     */
    private void record(Order order) {
        try {
            orderMapper.insert(order);
        } catch (DuplicateKeyException e) {
            throw new DuplicateOrderException(order.getIdempotencyKey());
        }
    }

    private void requireActiveAccount(Long accountId) {
        Account account = accountMapper.findById(accountId);
        if (account == null) {
            throw new AccountNotFoundException(accountId);
        }
        if (!account.isActive()) {
            throw new AccountNotActiveException(accountId, account.getStatus());
        }
    }

    /**
     * Authorisation, which is a different question from authentication and is answered in a different
     * place. The filter proved the caller holds a valid token. This decides whether that token
     * reaches this account.
     */
    private static void requireAccess(AuthenticatedUser user, Long accountId) {
        if (!user.canAccess(accountId)) {
            throw new AccountAccessDeniedException(user.subject(), accountId);
        }
    }
}

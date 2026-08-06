package com.tradingplatform.tradeapi.service;

import com.tradingplatform.domain.exception.AccountNotFoundException;
import com.tradingplatform.domain.model.Account;
import com.tradingplatform.domain.model.OrderStatus;
import com.tradingplatform.tradeapi.config.TradingProperties;
import com.tradingplatform.tradeapi.repository.AccountMapper;
import com.tradingplatform.tradeapi.repository.OrderMapper;
import com.tradingplatform.tradeapi.repository.PositionMapper;
import com.tradingplatform.tradeapi.security.AccountAccessDeniedException;
import com.tradingplatform.tradeapi.security.AuthenticatedUser;
import com.tradingplatform.tradeapi.web.dto.AccountResponse;
import com.tradingplatform.tradeapi.web.dto.BalanceResponse;
import com.tradingplatform.tradeapi.web.dto.OrderHistoryEntry;
import com.tradingplatform.tradeapi.web.dto.PositionResponse;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.util.List;

/**
 * The read side: account details, cash balance, holdings and the order blotter.
 *
 * <p>Every method authorises before it reads. The order is deliberate: a caller who may not reach an
 * account must not be able to learn whether it exists by timing the response or by reading a
 * different error.
 *
 * <p>A suspended or closed account can still be read. Business rule 2 governs placing and cancelling
 * orders, not looking at them, and a customer whose account has been suspended has an obvious right
 * to see the balance and the history. The 403 on these routes is the ownership failure only.
 *
 * <p>Read-only transactions, so that the driver and the database both know no write is coming.
 */
@Service
@Transactional(readOnly = true)
public class AccountService {

    private final AccountMapper accountMapper;
    private final PositionMapper positionMapper;
    private final OrderMapper orderMapper;
    private final TradingProperties properties;
    private final Clock clock;

    public AccountService(AccountMapper accountMapper,
                          PositionMapper positionMapper,
                          OrderMapper orderMapper,
                          TradingProperties properties,
                          Clock clock) {
        this.accountMapper = accountMapper;
        this.positionMapper = positionMapper;
        this.orderMapper = orderMapper;
        this.properties = properties;
        this.clock = clock;
    }

    /** Account details, including the optimistic lock version a client may echo back. */
    public AccountResponse getAccount(Long accountId, AuthenticatedUser user) {
        return AccountResponse.of(load(accountId, user));
    }

    /**
     * Available cash. Not portfolio value: that needs a live quote, and this service does not call
     * the Fauxnance API.
     *
     * <p>The currency is configured rather than stored. The schema holds no currency on
     * {@code accounts}, and inferring one from the instruments an account happens to hold would give a
     * different answer as the holdings change.
     */
    public BalanceResponse getBalance(Long accountId, AuthenticatedUser user) {
        return BalanceResponse.of(load(accountId, user), properties.baseCurrency(), clock.instant());
    }

    /** Holdings with a net quantity above zero. */
    public List<PositionResponse> getPositions(Long accountId, AuthenticatedUser user) {
        load(accountId, user);
        return positionMapper.findByAccount(accountId).stream()
                .map(PositionResponse::of)
                .toList();
    }

    /**
     * The blotter. Every order on the account, newest first, including rejected and cancelled ones,
     * because this is the audit trail and it is never filtered by default.
     */
    public List<OrderHistoryEntry> getOrders(Long accountId,
                                             OrderStatus status,
                                             Instant from,
                                             Instant to,
                                             AuthenticatedUser user) {
        load(accountId, user);
        return orderMapper.findByAccount(accountId, status, from, to).stream()
                .map(OrderHistoryEntry::of)
                .toList();
    }

    private Account load(Long accountId, AuthenticatedUser user) {
        if (!user.canAccess(accountId)) {
            throw new AccountAccessDeniedException(user.subject(), accountId);
        }
        Account account = accountMapper.findById(accountId);
        if (account == null) {
            throw new AccountNotFoundException(accountId);
        }
        return account;
    }
}

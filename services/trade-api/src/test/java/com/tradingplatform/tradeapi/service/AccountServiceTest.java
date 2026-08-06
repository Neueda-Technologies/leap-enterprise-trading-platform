package com.tradingplatform.tradeapi.service;

import com.tradingplatform.domain.exception.AccountNotFoundException;
import com.tradingplatform.domain.model.AccountStatus;
import com.tradingplatform.domain.model.OrderStatus;
import com.tradingplatform.tradeapi.TestData;
import com.tradingplatform.tradeapi.config.ExecutionMode;
import com.tradingplatform.tradeapi.repository.AccountMapper;
import com.tradingplatform.tradeapi.repository.OrderMapper;
import com.tradingplatform.tradeapi.repository.PositionMapper;
import com.tradingplatform.tradeapi.security.AccountAccessDeniedException;
import com.tradingplatform.tradeapi.web.dto.AccountResponse;
import com.tradingplatform.tradeapi.web.dto.BalanceResponse;
import com.tradingplatform.tradeapi.web.dto.OrderHistoryEntry;
import com.tradingplatform.tradeapi.web.dto.PositionResponse;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;

import static com.tradingplatform.tradeapi.TestData.ACCOUNT_ID;
import static com.tradingplatform.tradeapi.TestData.NOW;
import static com.tradingplatform.tradeapi.TestData.account;
import static com.tradingplatform.tradeapi.TestData.customer;
import static com.tradingplatform.tradeapi.TestData.customerOf;
import static com.tradingplatform.tradeapi.TestData.position;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@DisplayName("AccountService")
class AccountServiceTest {

    @Mock private AccountMapper accountMapper;
    @Mock private PositionMapper positionMapper;
    @Mock private OrderMapper orderMapper;

    private final Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);

    private AccountService service() {
        return new AccountService(accountMapper, positionMapper, orderMapper,
                TestData.properties(ExecutionMode.ASYNC), clock);
    }

    @Test
    @DisplayName("account details carry both identifiers and the lock version")
    void testGetAccount() {
        when(accountMapper.findById(ACCOUNT_ID)).thenReturn(account("24500.75", AccountStatus.ACTIVE, 7));

        AccountResponse response = service().getAccount(ACCOUNT_ID, customer());

        assertEquals(ACCOUNT_ID, response.id());
        assertEquals("ACC-000001", response.accountId());
        assertEquals(7, response.version());
        assertEquals(0, response.cashBalance().compareTo(TestData.money("24500.75")));
    }

    @Test
    void testGetAccount_NotFound() {
        when(accountMapper.findById(ACCOUNT_ID)).thenReturn(null);

        assertThrows(AccountNotFoundException.class, () -> service().getAccount(ACCOUNT_ID, customer()));
    }

    @Test
    @DisplayName("a token for another account is refused before the account is read")
    void testGetAccount_ForeignAccount() {
        assertThrows(AccountAccessDeniedException.class,
                () -> service().getAccount(ACCOUNT_ID, customerOf(2L)));

        verifyNoInteractions(accountMapper);
    }

    @Test
    @DisplayName("the balance is cash only, in the configured base currency")
    void testGetBalance() {
        when(accountMapper.findById(ACCOUNT_ID)).thenReturn(account("24500.75"));

        BalanceResponse response = service().getBalance(ACCOUNT_ID, customer());

        assertEquals(ACCOUNT_ID, response.accountId());
        assertEquals("USD", response.currency());
        assertEquals(NOW, response.asOf());
        assertEquals(0, response.cashBalance().compareTo(TestData.money("24500.75")));
    }

    @Test
    @DisplayName("a suspended account can still be read: rule 2 governs trading, not looking")
    void testGetBalance_SuspendedAccountIsReadable() {
        when(accountMapper.findById(ACCOUNT_ID))
                .thenReturn(account("24500.75", AccountStatus.SUSPENDED, 0));

        assertEquals(AccountStatus.SUSPENDED, service().getAccount(ACCOUNT_ID, customer()).status());
    }

    @Test
    void testGetPositions() {
        when(accountMapper.findById(ACCOUNT_ID)).thenReturn(account("100.00"));
        when(positionMapper.findByAccount(ACCOUNT_ID)).thenReturn(List.of(position(100, "25.50")));

        List<PositionResponse> positions = service().getPositions(ACCOUNT_ID, customer());

        assertEquals(1, positions.size());
        assertEquals("ACME", positions.getFirst().symbol());
        assertEquals(100, positions.getFirst().quantity());
    }

    @Test
    @DisplayName("the blotter carries the display prefix on the order identifier")
    void testGetOrders() {
        when(accountMapper.findById(ACCOUNT_ID)).thenReturn(account("100.00"));
        when(orderMapper.findByAccount(ACCOUNT_ID, null, null, null))
                .thenReturn(List.of(TestData.order(OrderStatus.FILLED)));

        List<OrderHistoryEntry> orders = service().getOrders(ACCOUNT_ID, null, null, null, customer());

        assertEquals(1, orders.size());
        assertTrue(orders.getFirst().orderId().startsWith("ORD-"));
        assertEquals(OrderStatus.FILLED, orders.getFirst().status());
    }

    @Test
    @DisplayName("the optional filters are passed through to the query, not applied in Java")
    void testGetOrders_PassesFiltersToTheMapper() {
        Instant from = Instant.parse("2026-09-01T00:00:00Z");
        Instant to = Instant.parse("2026-09-30T00:00:00Z");
        when(accountMapper.findById(ACCOUNT_ID)).thenReturn(account("100.00"));
        when(orderMapper.findByAccount(ACCOUNT_ID, OrderStatus.FILLED, from, to)).thenReturn(List.of());

        service().getOrders(ACCOUNT_ID, OrderStatus.FILLED, from, to, customer());

        verify(orderMapper).findByAccount(ACCOUNT_ID, OrderStatus.FILLED, from, to);
    }
}

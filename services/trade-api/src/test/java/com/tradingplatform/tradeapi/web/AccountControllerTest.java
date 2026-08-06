package com.tradingplatform.tradeapi.web;

import com.tradingplatform.domain.exception.AccountNotFoundException;
import com.tradingplatform.domain.model.AccountStatus;
import com.tradingplatform.domain.model.OrderSide;
import com.tradingplatform.domain.model.OrderStatus;
import com.tradingplatform.tradeapi.TestData;
import com.tradingplatform.tradeapi.security.AccountAccessDeniedException;
import com.tradingplatform.tradeapi.security.AuthenticatedUser;
import com.tradingplatform.tradeapi.service.AccountService;
import com.tradingplatform.tradeapi.web.dto.AccountResponse;
import com.tradingplatform.tradeapi.web.dto.BalanceResponse;
import com.tradingplatform.tradeapi.web.dto.OrderHistoryEntry;
import com.tradingplatform.tradeapi.web.dto.PositionResponse;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Instant;
import java.util.List;

import static com.tradingplatform.tradeapi.TestData.customer;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(AccountController.class)
@DisplayName("GET /api/v1/accounts")
class AccountControllerTest {

    @Autowired private MockMvc mockMvc;

    @MockitoBean private AccountService accountService;

    @Test
    @DisplayName("id is the numeric key and accountId is the business reference, in that order")
    void testGetAccount() throws Exception {
        when(accountService.getAccount(eq(1L), any())).thenReturn(new AccountResponse(
                1L, "ACC-000001", "Priya Menon", TestData.money("24500.75"),
                AccountStatus.ACTIVE, 7, TestData.NOW));

        mockMvc.perform(get("/api/v1/accounts/{id}", 1)
                        .requestAttr(AuthenticatedUser.ATTRIBUTE, customer()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(1))
                .andExpect(jsonPath("$.accountId").value("ACC-000001"))
                .andExpect(jsonPath("$.holderName").value("Priya Menon"))
                .andExpect(jsonPath("$.cashBalance").value(24500.75))
                .andExpect(jsonPath("$.status").value("ACTIVE"))
                .andExpect(jsonPath("$.version").value(7));
    }

    @Test
    void testGetAccount_NotFound() throws Exception {
        when(accountService.getAccount(eq(1L), any())).thenThrow(new AccountNotFoundException(1L));

        mockMvc.perform(get("/api/v1/accounts/{id}", 1)
                        .requestAttr(AuthenticatedUser.ATTRIBUTE, customer()))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.errorCode").value("ACC-404"));
    }

    @Test
    void testGetAccount_ForeignAccount() throws Exception {
        when(accountService.getAccount(eq(2L), any()))
                .thenThrow(new AccountAccessDeniedException("sub", 2L));

        mockMvc.perform(get("/api/v1/accounts/{id}", 2)
                        .requestAttr(AuthenticatedUser.ATTRIBUTE, customer()))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.errorCode").value("ACC-403"));
    }

    @Test
    @DisplayName("an account key of zero is not an identifier")
    void testGetAccount_NonPositiveKey() throws Exception {
        mockMvc.perform(get("/api/v1/accounts/{id}", 0)
                        .requestAttr(AuthenticatedUser.ATTRIBUTE, customer()))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.errorCode").value("VAL-422"));
    }

    @Test
    void testGetBalance() throws Exception {
        when(accountService.getBalance(eq(1L), any())).thenReturn(
                new BalanceResponse(1L, TestData.money("24500.75"), "USD", TestData.NOW));

        mockMvc.perform(get("/api/v1/accounts/{id}/balance", 1)
                        .requestAttr(AuthenticatedUser.ATTRIBUTE, customer()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accountId").value(1))
                .andExpect(jsonPath("$.cashBalance").value(24500.75))
                .andExpect(jsonPath("$.currency").value("USD"))
                .andExpect(jsonPath("$.asOf").value("2026-09-28T09:14:22Z"));
    }

    @Test
    void testGetPositions() throws Exception {
        when(accountService.getPositions(eq(1L), any())).thenReturn(List.of(
                new PositionResponse(1L, "ACME", 100, TestData.money("25.50")),
                new PositionResponse(1L, "INFY.NS", 40, TestData.money("1580.25"))));

        mockMvc.perform(get("/api/v1/accounts/{id}/positions", 1)
                        .requestAttr(AuthenticatedUser.ATTRIBUTE, customer()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].symbol").value("ACME"))
                .andExpect(jsonPath("$[0].quantity").value(100))
                .andExpect(jsonPath("$[1].averageCost").value(1580.25));
    }

    @Test
    @DisplayName("the blotter carries the limit price and the executed price separately")
    void testGetOrders() throws Exception {
        when(accountService.getOrders(eq(1L), any(), any(), any(), any())).thenReturn(List.of(
                new OrderHistoryEntry("ORD-" + TestData.ORDER_ID, 1L, "ACME", OrderSide.BUY, 100,
                        TestData.money("25.50"), TestData.money("25.48"), OrderStatus.FILLED,
                        TestData.IDEMPOTENCY_KEY, TestData.NOW)));

        mockMvc.perform(get("/api/v1/accounts/{id}/orders", 1)
                        .requestAttr(AuthenticatedUser.ATTRIBUTE, customer()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].price").value(25.50))
                .andExpect(jsonPath("$[0].executedPrice").value(25.48))
                .andExpect(jsonPath("$[0].status").value("FILLED"));
    }

    @Test
    @DisplayName("the optional filters bind and reach the service")
    void testGetOrders_WithFilters() throws Exception {
        when(accountService.getOrders(any(), any(), any(), any(), any())).thenReturn(List.of());

        mockMvc.perform(get("/api/v1/accounts/{id}/orders", 1)
                        .param("status", "FILLED")
                        .param("from", "2026-09-01T00:00:00Z")
                        .param("to", "2026-09-30T00:00:00Z")
                        .requestAttr(AuthenticatedUser.ATTRIBUTE, customer()))
                .andExpect(status().isOk());

        verify(accountService).getOrders(1L, OrderStatus.FILLED,
                Instant.parse("2026-09-01T00:00:00Z"), Instant.parse("2026-09-30T00:00:00Z"),
                customer());
    }

    @Test
    void testGetOrders_UnknownStatusFilter() throws Exception {
        mockMvc.perform(get("/api/v1/accounts/{id}/orders", 1)
                        .param("status", "PARTIAL")
                        .requestAttr(AuthenticatedUser.ATTRIBUTE, customer()))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.errorCode").value("VAL-422"));
    }
}

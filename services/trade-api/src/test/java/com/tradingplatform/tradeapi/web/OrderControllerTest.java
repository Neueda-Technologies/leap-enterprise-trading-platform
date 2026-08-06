package com.tradingplatform.tradeapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.tradingplatform.domain.exception.AccountNotActiveException;
import com.tradingplatform.domain.exception.AccountNotFoundException;
import com.tradingplatform.domain.exception.DuplicateOrderException;
import com.tradingplatform.domain.exception.InstrumentNotFoundException;
import com.tradingplatform.domain.exception.InsufficientFundsException;
import com.tradingplatform.domain.exception.InsufficientHoldingsException;
import com.tradingplatform.domain.exception.OrderNotCancellableException;
import com.tradingplatform.domain.exception.OrderNotFoundException;
import com.tradingplatform.domain.model.AccountStatus;
import com.tradingplatform.domain.model.OrderSide;
import com.tradingplatform.domain.model.OrderStatus;
import com.tradingplatform.tradeapi.TestData;
import com.tradingplatform.tradeapi.security.AccountAccessDeniedException;
import com.tradingplatform.tradeapi.security.AuthenticatedUser;
import com.tradingplatform.tradeapi.service.ConcurrentUpdateException;
import com.tradingplatform.tradeapi.service.OrderService;
import com.tradingplatform.tradeapi.web.dto.OrderResponse;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.util.Map;

import static com.tradingplatform.tradeapi.TestData.customer;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The order endpoints and the error catalogue.
 *
 * <p>A slice test: the web layer and the exception handler, with the service mocked. The JWT filter
 * is registered by URL pattern in a plain {@code @Configuration} and is therefore not part of this
 * slice, so the tests set the authenticated user attribute the filter would have set. Its own
 * behaviour is proved separately in {@code JwtAuthenticationFilterTest}.
 */
@WebMvcTest(OrderController.class)
@DisplayName("POST and DELETE /api/v1/orders")
class OrderControllerTest {

    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;

    @MockitoBean private OrderService orderService;

    private MockHttpServletRequestBuilder placeOrder(Object body) throws Exception {
        return post("/api/v1/orders")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(body))
                .requestAttr(AuthenticatedUser.ATTRIBUTE, customer());
    }

    private static Map<String, Object> validBody() {
        return Map.of(
                "accountId", 1,
                "symbol", "ACME",
                "side", "BUY",
                "quantity", 100,
                "price", 25.50,
                "idempotencyKey", TestData.IDEMPOTENCY_KEY);
    }

    @Nested
    @DisplayName("placing an order")
    class Placing {

        @Test
        void testPlaceOrder_Accepted() throws Exception {
            when(orderService.placeOrder(any(), any())).thenReturn(new OrderResponse(
                    "ORD-" + TestData.ORDER_ID, OrderStatus.NEW, "Order accepted",
                    "ACME", OrderSide.BUY, 100, TestData.money("25.50")));

            mockMvc.perform(placeOrder(validBody()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.orderId").value("ORD-" + TestData.ORDER_ID))
                    .andExpect(jsonPath("$.status").value("NEW"))
                    .andExpect(jsonPath("$.message").value("Order accepted"))
                    .andExpect(jsonPath("$.symbol").value("ACME"))
                    .andExpect(jsonPath("$.side").value("BUY"))
                    .andExpect(jsonPath("$.quantity").value(100))
                    .andExpect(jsonPath("$.price").value(25.50));
        }

        @Test
        @DisplayName("a synchronous fill returns the terminal status under the same schema")
        void testPlaceOrder_Filled() throws Exception {
            when(orderService.placeOrder(any(), any())).thenReturn(new OrderResponse(
                    "ORD-" + TestData.ORDER_ID, OrderStatus.FILLED, "Order executed",
                    "ACME", OrderSide.BUY, 100, TestData.money("25.50")));

            mockMvc.perform(placeOrder(validBody()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("FILLED"));
        }
    }

    @Nested
    @DisplayName("field validation is VAL-422, before any rule is evaluated")
    class Validation {

        @Test
        void testPlaceOrder_ZeroQuantity() throws Exception {
            Map<String, Object> body = new java.util.HashMap<>(validBody());
            body.put("quantity", 0);

            mockMvc.perform(placeOrder(body))
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.errorCode").value("VAL-422"))
                    .andExpect(jsonPath("$.message").value("Invalid input"));
        }

        @Test
        void testPlaceOrder_ZeroPrice() throws Exception {
            Map<String, Object> body = new java.util.HashMap<>(validBody());
            body.put("price", 0);

            mockMvc.perform(placeOrder(body))
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.errorCode").value("VAL-422"));
        }

        @Test
        void testPlaceOrder_MissingIdempotencyKey() throws Exception {
            Map<String, Object> body = new java.util.HashMap<>(validBody());
            body.remove("idempotencyKey");

            mockMvc.perform(placeOrder(body))
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.errorCode").value("VAL-422"));
        }

        @Test
        @DisplayName("an unknown side is a binding failure, not a 500")
        void testPlaceOrder_UnknownSide() throws Exception {
            Map<String, Object> body = new java.util.HashMap<>(validBody());
            body.put("side", "SHORT");

            mockMvc.perform(placeOrder(body))
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.errorCode").value("VAL-422"));
        }

        @Test
        void testPlaceOrder_MalformedBody() throws Exception {
            mockMvc.perform(post("/api/v1/orders")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{ not json")
                            .requestAttr(AuthenticatedUser.ATTRIBUTE, customer()))
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.errorCode").value("VAL-422"));
        }

        @Test
        @DisplayName("the error body never carries a class name or a stack trace")
        void testErrorBodyLeaksNothing() throws Exception {
            Map<String, Object> body = new java.util.HashMap<>(validBody());
            body.put("quantity", 0);

            String rendered = mockMvc.perform(placeOrder(body))
                    .andReturn().getResponse().getContentAsString();

            org.junit.jupiter.api.Assertions.assertEquals(
                    "{\"errorCode\":\"VAL-422\",\"message\":\"Invalid input\"}", rendered);
        }
    }

    @Nested
    @DisplayName("every domain exception maps to its documented code and status")
    class ErrorCatalogue {

        @Test
        void testAccountNotFound() throws Exception {
            when(orderService.placeOrder(any(), any())).thenThrow(new AccountNotFoundException(1L));

            mockMvc.perform(placeOrder(validBody()))
                    .andExpect(status().isNotFound())
                    .andExpect(jsonPath("$.errorCode").value("ACC-404"))
                    .andExpect(jsonPath("$.message").value("Account not found"));
        }

        @Test
        void testAccountNotActive() throws Exception {
            when(orderService.placeOrder(any(), any()))
                    .thenThrow(new AccountNotActiveException(1L, AccountStatus.SUSPENDED));

            mockMvc.perform(placeOrder(validBody()))
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.errorCode").value("ACC-403"))
                    .andExpect(jsonPath("$.message").value("Account not active"));
        }

        @Test
        @DisplayName("an ownership failure answers exactly as a suspended account does")
        void testAccessDenied() throws Exception {
            when(orderService.placeOrder(any(), any()))
                    .thenThrow(new AccountAccessDeniedException("sub", 2L));

            mockMvc.perform(placeOrder(validBody()))
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.errorCode").value("ACC-403"))
                    .andExpect(jsonPath("$.message").value("Account not active"));
        }

        @Test
        void testInstrumentNotFound() throws Exception {
            when(orderService.placeOrder(any(), any()))
                    .thenThrow(new InstrumentNotFoundException("ACME"));

            mockMvc.perform(placeOrder(validBody()))
                    .andExpect(status().isNotFound())
                    .andExpect(jsonPath("$.errorCode").value("INS-404"))
                    .andExpect(jsonPath("$.message").value("Instrument not found"));
        }

        @Test
        void testInsufficientFunds() throws Exception {
            when(orderService.placeOrder(any(), any())).thenThrow(
                    new InsufficientFundsException(TestData.money("2550.00"), TestData.money("10.00")));

            mockMvc.perform(placeOrder(validBody()))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.errorCode").value("ORD-400"))
                    .andExpect(jsonPath("$.message").value("Insufficient funds"));
        }

        @Test
        void testInsufficientHoldings() throws Exception {
            when(orderService.placeOrder(any(), any()))
                    .thenThrow(new InsufficientHoldingsException("ACME", 100, 10));

            mockMvc.perform(placeOrder(validBody()))
                    .andExpect(status().isConflict())
                    .andExpect(jsonPath("$.errorCode").value("ORD-409"))
                    .andExpect(jsonPath("$.message").value("Insufficient holdings"));
        }

        @Test
        void testDuplicateOrder() throws Exception {
            when(orderService.placeOrder(any(), any()))
                    .thenThrow(new DuplicateOrderException(TestData.IDEMPOTENCY_KEY));

            mockMvc.perform(placeOrder(validBody()))
                    .andExpect(status().isConflict())
                    .andExpect(jsonPath("$.errorCode").value("ORD-409"))
                    .andExpect(jsonPath("$.message").value("Duplicate order"));
        }

        @Test
        @DisplayName("a lost optimistic lock is a conflict the client should retry")
        void testConcurrentUpdate() throws Exception {
            when(orderService.placeOrder(any(), any()))
                    .thenThrow(new ConcurrentUpdateException("accounts.version moved"));

            mockMvc.perform(placeOrder(validBody()))
                    .andExpect(status().isConflict())
                    .andExpect(jsonPath("$.errorCode").value("ORD-409"));
        }
    }

    @Nested
    @DisplayName("cancelling an order")
    class Cancelling {

        @Test
        void testCancelOrder_Cancelled() throws Exception {
            when(orderService.cancelOrder(any(), any())).thenReturn(new OrderResponse(
                    "ORD-" + TestData.ORDER_ID, OrderStatus.CANCELLED, "Order cancelled",
                    "ACME", OrderSide.BUY, 100, TestData.money("25.50")));

            mockMvc.perform(delete("/api/v1/orders/{id}", TestData.ORDER_ID)
                            .requestAttr(AuthenticatedUser.ATTRIBUTE, customer()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("CANCELLED"))
                    .andExpect(jsonPath("$.message").value("Order cancelled"));
        }

        @Test
        @DisplayName("an unknown order is 404 carrying ORD-409, exactly as the contract defines it")
        void testCancelOrder_NotFound() throws Exception {
            when(orderService.cancelOrder(any(), any()))
                    .thenThrow(new OrderNotFoundException(TestData.ORDER_ID));

            mockMvc.perform(delete("/api/v1/orders/{id}", TestData.ORDER_ID)
                            .requestAttr(AuthenticatedUser.ATTRIBUTE, customer()))
                    .andExpect(status().isNotFound())
                    .andExpect(jsonPath("$.errorCode").value("ORD-409"))
                    .andExpect(jsonPath("$.message").value("Order not found"));
        }

        @Test
        void testCancelOrder_NotCancellable() throws Exception {
            when(orderService.cancelOrder(any(), any()))
                    .thenThrow(new OrderNotCancellableException(TestData.ORDER_ID, OrderStatus.FILLED));

            mockMvc.perform(delete("/api/v1/orders/{id}", TestData.ORDER_ID)
                            .requestAttr(AuthenticatedUser.ATTRIBUTE, customer()))
                    .andExpect(status().isConflict())
                    .andExpect(jsonPath("$.errorCode").value("ORD-409"))
                    .andExpect(jsonPath("$.message").value("Order is not cancellable"));
        }

        @Test
        @DisplayName("the path carries the UUID without the ORD- display prefix")
        void testCancelOrder_PrefixedIdentifierIsRefused() throws Exception {
            mockMvc.perform(delete("/api/v1/orders/{id}", "ORD-" + TestData.ORDER_ID)
                            .requestAttr(AuthenticatedUser.ATTRIBUTE, customer()))
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.errorCode").value("VAL-422"));
        }
    }
}

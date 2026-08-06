package com.tradingplatform.tradeapi.web;

import com.tradingplatform.domain.model.OrderStatus;
import com.tradingplatform.tradeapi.security.AuthenticatedUser;
import com.tradingplatform.tradeapi.service.AccountService;
import com.tradingplatform.tradeapi.web.dto.AccountResponse;
import com.tradingplatform.tradeapi.web.dto.BalanceResponse;
import com.tradingplatform.tradeapi.web.dto.ErrorResponse;
import com.tradingplatform.tradeapi.web.dto.OrderHistoryEntry;
import com.tradingplatform.tradeapi.web.dto.PositionResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.constraints.Min;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.MediaType;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.List;

/**
 * Account details, balance, holdings and order history.
 *
 * <p>The path parameter {@code id} is the numeric account key, {@code accounts.id}. It is not the
 * string business reference, which is returned as {@code AccountResponse.accountId} and is the one
 * place in the contract where that name means the other thing.
 */
@RestController
@RequestMapping(path = "/api/v1/accounts", produces = MediaType.APPLICATION_JSON_VALUE)
@Validated
@Tag(name = "Accounts", description = "Account details, cash balance, holdings and order history.")
public class AccountController {

    private final AccountService accountService;

    public AccountController(AccountService accountService) {
        this.accountService = accountService;
    }

    @GetMapping("/{id}")
    @Operation(operationId = "getAccount", summary = "Get account details")
    @ApiResponse(responseCode = "200", description = "Account details.")
    @ApiResponse(responseCode = "401", description = "Missing, malformed, expired or wrongly signed token.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    @ApiResponse(responseCode = "403", description = "Not reachable with this token.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    @ApiResponse(responseCode = "404", description = "No account exists with that key.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    public AccountResponse getAccount(
            @PathVariable("id") @Min(1) Long id,
            @RequestAttribute(AuthenticatedUser.ATTRIBUTE) AuthenticatedUser user) {

        return accountService.getAccount(id, user);
    }

    @GetMapping("/{id}/balance")
    @Operation(
            operationId = "getBalance",
            summary = "Get cash balance",
            description = """
                    Returns available cash only. It does not include the market value of holdings.
                    Portfolio valuation is the Sprint 10 Portfolio and P&L extension, contracted
                    separately.""")
    @ApiResponse(responseCode = "200", description = "Cash balance.")
    @ApiResponse(responseCode = "404", description = "No account exists with that key.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    public BalanceResponse getBalance(
            @PathVariable("id") @Min(1) Long id,
            @RequestAttribute(AuthenticatedUser.ATTRIBUTE) AuthenticatedUser user) {

        return accountService.getBalance(id, user);
    }

    @GetMapping("/{id}/positions")
    @Operation(
            operationId = "getPositions",
            summary = "Get holdings",
            description = """
                    Net held quantity and average cost per instrument. Positions with a net quantity
                    of zero are not returned. Market value is not calculated here; it needs a live
                    quote and belongs to the Portfolio and P&L extension.""")
    @ApiResponse(responseCode = "200", description = "Holdings for the account.")
    @ApiResponse(responseCode = "404", description = "No account exists with that key.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    public List<PositionResponse> getPositions(
            @PathVariable("id") @Min(1) Long id,
            @RequestAttribute(AuthenticatedUser.ATTRIBUTE) AuthenticatedUser user) {

        return accountService.getPositions(id, user);
    }

    @GetMapping("/{id}/orders")
    @Operation(
            operationId = "getOrders",
            summary = "Get order history",
            description = """
                    Every order recorded against the account, newest first, including rejected and
                    cancelled ones. This is the audit trail and it is never filtered by default.""")
    @ApiResponse(responseCode = "200", description = "Order history for the account.")
    @ApiResponse(responseCode = "404", description = "No account exists with that key.",
            content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    public List<OrderHistoryEntry> getOrders(
            @PathVariable("id") @Min(1) Long id,
            @Parameter(description = "Restrict to one order status.")
            @RequestParam(value = "status", required = false) OrderStatus status,
            @Parameter(description = "Include orders created on or after this instant.")
            @RequestParam(value = "from", required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Instant from,
            @Parameter(description = "Include orders created on or before this instant.")
            @RequestParam(value = "to", required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Instant to,
            @RequestAttribute(AuthenticatedUser.ATTRIBUTE) AuthenticatedUser user) {

        return accountService.getOrders(id, status, from, to, user);
    }
}

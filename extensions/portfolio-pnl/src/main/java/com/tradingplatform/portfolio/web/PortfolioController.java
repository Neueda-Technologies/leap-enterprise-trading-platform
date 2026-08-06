package com.tradingplatform.portfolio.web;

import com.tradingplatform.portfolio.exception.ForbiddenException;
import com.tradingplatform.portfolio.security.AuthenticatedPrincipal;
import com.tradingplatform.portfolio.security.PrincipalContext;
import com.tradingplatform.portfolio.service.PortfolioService;
import com.tradingplatform.portfolio.web.dto.PnlResponse;
import com.tradingplatform.portfolio.web.dto.PortfolioSummaryResponse;
import com.tradingplatform.portfolio.web.dto.PricedPositionResponse;
import java.time.LocalDate;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Implements the three operations tagged {@code Portfolio} and {@code P&L} in
 * docs/contracts/portfolio-api.yaml. Every route here is under {@code /api/**} and is
 * therefore covered by {@link com.tradingplatform.portfolio.security.JwtAuthenticationFilter}.
 */
@RestController
@RequestMapping("/api/v1/portfolio")
public class PortfolioController {

    private final PortfolioService portfolioService;

    public PortfolioController(PortfolioService portfolioService) {
        this.portfolioService = portfolioService;
    }

    @GetMapping("/{accountId}")
    public PortfolioSummaryResponse getSummary(@PathVariable long accountId) {
        requireOwnAccount(accountId);
        return portfolioService.getSummary(accountId);
    }

    @GetMapping("/{accountId}/positions")
    public List<PricedPositionResponse> getPositions(
            @PathVariable long accountId, @RequestParam(required = false) String symbol) {
        requireOwnAccount(accountId);
        return portfolioService.getPositions(accountId, symbol);
    }

    @GetMapping("/{accountId}/pnl")
    public PnlResponse getPnl(
            @PathVariable long accountId,
            @RequestParam(required = false) LocalDate from,
            @RequestParam(required = false) LocalDate to,
            @RequestParam(required = false, defaultValue = "false") boolean bySymbol) {
        requireOwnAccount(accountId);
        return portfolioService.getPnl(accountId, from, to, bySymbol);
    }

    /**
     * Compares the token's {@code accountId} claim against the account requested in
     * the path. This service verifies the token itself and does not trust an upstream
     * to have already checked it, per the security note on {@code bearerAuth} in
     * portfolio-api.yaml.
     */
    private void requireOwnAccount(long accountId) {
        AuthenticatedPrincipal principal = PrincipalContext.get();
        if (principal == null || principal.accountId() != accountId) {
            throw new ForbiddenException();
        }
    }
}

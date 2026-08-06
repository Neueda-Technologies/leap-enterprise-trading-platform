package com.tradingplatform.tradeapi.web.dto;

import com.tradingplatform.domain.model.Account;
import io.swagger.v3.oas.annotations.media.Schema;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * Available cash, and nothing else.
 *
 * <p>It does not include the market value of holdings. Valuing a position needs a live quote, which
 * needs a call to the Fauxnance API, which this service does not make. Portfolio valuation is the
 * Sprint 10 Portfolio and P&amp;L extension and is contracted separately.
 *
 * @param accountId   the numeric account key
 * @param cashBalance available cash
 * @param currency    ISO 4217 code
 * @param asOf        when the balance was read
 */
@Schema(name = "BalanceResponse")
public record BalanceResponse(

        @Schema(example = "1") Long accountId,

        @Schema(example = "24500.75") BigDecimal cashBalance,

        @Schema(description = "ISO 4217 code.", example = "USD") String currency,

        Instant asOf) {

    public static BalanceResponse of(Account account, String currency, Instant asOf) {
        return new BalanceResponse(account.getId(), account.getCashBalance(), currency, asOf);
    }
}

package com.tradingplatform.tradeapi.web.dto;

import com.tradingplatform.domain.model.Account;
import com.tradingplatform.domain.model.AccountStatus;
import io.swagger.v3.oas.annotations.media.Schema;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * Account details.
 *
 * <p>This is the one place in the whole contract where the name {@code accountId} means the string
 * business reference rather than the numeric key. {@code id} is the numeric key, and it is what every
 * other endpoint, the JWT claim, {@code orders.account_id} and every Kafka payload call
 * {@code accountId}. The collision exists because the source domain model defines both identifiers.
 * Renaming either field breaks the generated Angular client.
 *
 * @param id          the numeric account key, {@code accounts.id}
 * @param accountId   the business account reference, {@code accounts.account_id}
 * @param holderName  the customer's name
 * @param cashBalance available cash, to two decimal places
 * @param status      ACTIVE, SUSPENDED or CLOSED
 * @param version     optimistic lock version, incremented on every write to the row
 * @param lastUpdated when the row last changed
 */
@Schema(name = "AccountResponse")
public record AccountResponse(

        @Schema(description = "The numeric account key. This is what every other endpoint calls "
                + "accountId.", example = "1")
        Long id,

        @Schema(description = "The business account reference.", example = "ACC-000001")
        String accountId,

        @Schema(example = "Priya Menon") String holderName,

        @Schema(example = "24500.75") BigDecimal cashBalance,

        AccountStatus status,

        @Schema(example = "7") int version,

        Instant lastUpdated) {

    public static AccountResponse of(Account account) {
        return new AccountResponse(
                account.getId(),
                account.getAccountId(),
                account.getHolderName(),
                account.getCashBalance(),
                account.getStatus(),
                account.getVersion(),
                account.getLastUpdated());
    }
}

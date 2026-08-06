package com.tradingplatform.portfolio.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;

/**
 * Maps {@code accounts}, per docs/contracts/database-schema.sql. Read-only from this
 * service: the Trade REST API and the Trade Executor own writes to this table.
 *
 * <p>{@code id} is the numeric surrogate key. That is what "accountId" means
 * throughout the portfolio API, matching the JWT {@code accountId} claim and
 * {@code positions.account_id}. It is not {@code accounts.account_id}, the business
 * reference string; see the naming-collision note at the top of database-schema.sql.
 */
@Entity
@Table(name = "accounts")
public class AccountEntity {

    @Id
    private Long id;

    @Column(name = "account_id")
    private String businessAccountId;

    @Column(name = "holder_name")
    private String holderName;

    @Column(name = "cash_balance")
    private BigDecimal cashBalance;

    private String status;

    public Long getId() {
        return id;
    }

    public String getBusinessAccountId() {
        return businessAccountId;
    }

    public String getHolderName() {
        return holderName;
    }

    public BigDecimal getCashBalance() {
        return cashBalance;
    }

    public String getStatus() {
        return status;
    }
}

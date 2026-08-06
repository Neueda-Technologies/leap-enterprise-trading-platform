package com.tradingplatform.portfolio.domain;

import java.io.Serializable;
import java.util.Objects;

/** Composite key for {@code positions}: {@code (account_id, symbol)}. */
public class PositionId implements Serializable {

    private Long accountId;
    private String symbol;

    public PositionId() {
    }

    public PositionId(Long accountId, String symbol) {
        this.accountId = accountId;
        this.symbol = symbol;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof PositionId that)) {
            return false;
        }
        return Objects.equals(accountId, that.accountId) && Objects.equals(symbol, that.symbol);
    }

    @Override
    public int hashCode() {
        return Objects.hash(accountId, symbol);
    }
}

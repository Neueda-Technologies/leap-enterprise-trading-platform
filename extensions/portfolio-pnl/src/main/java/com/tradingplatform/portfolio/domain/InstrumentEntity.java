package com.tradingplatform.portfolio.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** Maps {@code instruments}, per docs/contracts/database-schema.sql. Read-only reference data. */
@Entity
@Table(name = "instruments")
public class InstrumentEntity {

    @Id
    private String symbol;

    private String name;

    @Column(name = "asset_class")
    private String assetClass;

    private String currency;

    private Boolean tradable;

    public String getSymbol() {
        return symbol;
    }

    public String getName() {
        return name;
    }

    public String getAssetClass() {
        return assetClass;
    }

    public String getCurrency() {
        return currency;
    }

    public Boolean getTradable() {
        return tradable;
    }
}

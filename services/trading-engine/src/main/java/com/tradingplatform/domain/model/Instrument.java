package com.tradingplatform.domain.model;

import java.util.Objects;

/**
 * A tradable security. Reference data, read on every order and written almost never.
 *
 * <p>The symbol is the natural key. It is externally assigned by the venue, stable, and already
 * carried on every order and every Fauxnance request, so a surrogate key would add a join without
 * adding anything.
 *
 * <p>{@link #isTradable()} is business rule 3. Trading in an instrument is suspended by setting the
 * flag to false, never by deleting the row: the order history references the symbol and that history
 * is the audit trail.
 */
public class Instrument {

    private final String symbol;
    private final String name;
    private final String assetClass;
    private final String currency;
    private boolean tradable;

    public Instrument(String symbol, String name, String assetClass, String currency, boolean tradable) {
        this.symbol = Objects.requireNonNull(symbol, "symbol");
        this.name = Objects.requireNonNull(name, "name");
        this.assetClass = Objects.requireNonNull(assetClass, "assetClass");
        this.currency = Objects.requireNonNull(currency, "currency");
        this.tradable = tradable;
    }

    /**
     * True when orders may be placed in this instrument. False suspends trading without losing the
     * reference data.
     */
    public boolean isTradable() {
        return tradable;
    }

    /** Suspends or resumes trading in the instrument. */
    public void setTradable(boolean tradable) {
        this.tradable = tradable;
    }

    /**
     * The venue symbol in the Fauxnance scheme: a plain ticker for a US equity or ETF, a
     * {@code .NS} or {@code .BO} suffix for NSE or BSE, an {@code FX:} prefix for a currency pair,
     * an {@code X:} prefix for crypto.
     */
    public String getSymbol() {
        return symbol;
    }

    public String getName() {
        return name;
    }

    /** One of {@code EQUITY}, {@code ETF}, {@code FX}, {@code CRYPTO}, {@code BOND}. */
    public String getAssetClass() {
        return assetClass;
    }

    /** ISO 4217 code the instrument is quoted in. */
    public String getCurrency() {
        return currency;
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        return other instanceof Instrument instrument && symbol.equals(instrument.symbol);
    }

    @Override
    public int hashCode() {
        return symbol.hashCode();
    }

    @Override
    public String toString() {
        return "Instrument[symbol=" + symbol + ", tradable=" + tradable + "]";
    }
}

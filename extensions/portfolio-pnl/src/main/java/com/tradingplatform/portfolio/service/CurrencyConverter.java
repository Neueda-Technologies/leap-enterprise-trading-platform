package com.tradingplatform.portfolio.service;

import com.tradingplatform.portfolio.fauxnance.Quote;
import com.tradingplatform.portfolio.fauxnance.QuoteCache;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Optional;
import java.util.Set;
import org.springframework.stereotype.Component;

/**
 * Converts an amount from an instrument's own currency into the account's base
 * currency, using the {@code FX:} pairs Fauxnance serves, per the note on
 * {@code PortfolioSummary.baseCurrency} in portfolio-api.yaml.
 *
 * <p>Convention: the symbol {@code FX:EURUSD} quotes the price of one EUR in USD, so
 * converting an EUR amount to USD multiplies by that quote. A team without FX coverage
 * for its chosen instruments should restrict its instrument universe to one currency
 * instead of guessing at an unsupported pair, per the escape hatch the contract
 * documents.
 */
@Component
public class CurrencyConverter {

    private final QuoteCache quoteCache;

    public CurrencyConverter(QuoteCache quoteCache) {
        this.quoteCache = quoteCache;
    }

    /** Returns empty when the currencies differ and no FX quote is available. */
    public Optional<BigDecimal> convert(BigDecimal amount, String fromCurrency, String toCurrency) {
        if (fromCurrency == null || fromCurrency.equalsIgnoreCase(toCurrency)) {
            return Optional.of(amount);
        }
        String pairSymbol = "FX:" + fromCurrency.toUpperCase() + toCurrency.toUpperCase();
        Quote rate = quoteCache.getQuotes(Set.of(pairSymbol)).get(pairSymbol);
        if (rate == null || rate.price() == null) {
            return Optional.empty();
        }
        return Optional.of(amount.multiply(rate.price()).setScale(2, RoundingMode.HALF_UP));
    }
}

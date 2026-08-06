package com.tradingplatform.portfolio.service;

import com.tradingplatform.portfolio.config.PortfolioProperties;
import com.tradingplatform.portfolio.domain.AccountEntity;
import com.tradingplatform.portfolio.domain.InstrumentEntity;
import com.tradingplatform.portfolio.domain.PositionEntity;
import com.tradingplatform.portfolio.exception.AccountNotFoundException;
import com.tradingplatform.portfolio.exception.InvalidInputException;
import com.tradingplatform.portfolio.exception.PricingUnavailableException;
import com.tradingplatform.portfolio.fauxnance.Quote;
import com.tradingplatform.portfolio.fauxnance.QuoteCache;
import com.tradingplatform.portfolio.ledger.PnlLedgerService;
import com.tradingplatform.portfolio.ledger.RealisedPnlEntry;
import com.tradingplatform.portfolio.pnl.PnlCalculator;
import com.tradingplatform.portfolio.repository.AccountRepository;
import com.tradingplatform.portfolio.repository.InstrumentRepository;
import com.tradingplatform.portfolio.repository.PositionRepository;
import com.tradingplatform.portfolio.web.dto.PnlResponse;
import com.tradingplatform.portfolio.web.dto.PortfolioSummaryResponse;
import com.tradingplatform.portfolio.web.dto.PricedPositionResponse;
import com.tradingplatform.portfolio.web.dto.SymbolPnl;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import org.springframework.stereotype.Service;

/**
 * Assembles the three portfolio views from priced positions, the account's cash
 * balance, and the realised profit-and-loss ledger. This is where the "Definitions"
 * section of portfolio-api.yaml is applied to real rows, using the arithmetic in
 * {@link PnlCalculator}.
 */
@Service
public class PortfolioService {

    private final AccountRepository accountRepository;
    private final PositionRepository positionRepository;
    private final InstrumentRepository instrumentRepository;
    private final QuoteCache quoteCache;
    private final CurrencyConverter currencyConverter;
    private final PnlLedgerService pnlLedgerService;
    private final PortfolioProperties portfolioProperties;
    private final Clock clock;

    public PortfolioService(
            AccountRepository accountRepository,
            PositionRepository positionRepository,
            InstrumentRepository instrumentRepository,
            QuoteCache quoteCache,
            CurrencyConverter currencyConverter,
            PnlLedgerService pnlLedgerService,
            PortfolioProperties portfolioProperties,
            Clock clock) {
        this.accountRepository = accountRepository;
        this.positionRepository = positionRepository;
        this.instrumentRepository = instrumentRepository;
        this.quoteCache = quoteCache;
        this.currencyConverter = currencyConverter;
        this.pnlLedgerService = pnlLedgerService;
        this.portfolioProperties = portfolioProperties;
        this.clock = clock;
    }

    public PortfolioSummaryResponse getSummary(long accountId) {
        AccountEntity account = requireAccount(accountId);
        List<PricedHolding> holdings = priceHoldings(accountId, null);
        requirePricingUnlessEmpty(holdings);

        String baseCurrency = portfolioProperties.baseCurrency();
        boolean partial = holdings.stream().anyMatch(h -> !h.priced() || !h.convertible());

        BigDecimal marketValue = holdings.stream()
                .filter(h -> h.priced() && h.convertible())
                .map(PricedHolding::marketValueInBaseCurrency)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        BigDecimal costBasis = holdings.stream()
                .filter(h -> h.priced() && h.convertible())
                .map(PricedHolding::costBasisInBaseCurrency)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        BigDecimal unrealisedPnl = PnlCalculator.unrealisedPnl(marketValue, costBasis);
        BigDecimal unrealisedPnlPercent = PnlCalculator.unrealisedPnlPercent(unrealisedPnl, costBasis);
        BigDecimal realisedPnl = totalRealisedPnl(accountId);
        BigDecimal totalValue = PnlCalculator.totalValue(account.getCashBalance(), marketValue);

        return new PortfolioSummaryResponse(
                accountId,
                baseCurrency,
                account.getCashBalance(),
                marketValue,
                costBasis,
                unrealisedPnl,
                unrealisedPnlPercent,
                realisedPnl,
                totalValue,
                holdings.size(),
                partial,
                clock.instant());
    }

    public List<PricedPositionResponse> getPositions(long accountId, String symbolFilter) {
        requireAccount(accountId);
        List<PricedHolding> holdings = priceHoldings(accountId, symbolFilter);
        requirePricingUnlessEmpty(holdings);

        return holdings.stream()
                .map(h -> new PricedPositionResponse(
                        accountId,
                        h.symbol(),
                        h.quantity(),
                        h.averageCost(),
                        h.costBasis(),
                        h.lastPrice(),
                        h.marketValue(),
                        h.unrealisedPnl(),
                        h.unrealisedPnlPercent(),
                        h.currency(),
                        h.priceAsOf(),
                        h.stale()))
                .toList();
    }

    public PnlResponse getPnl(long accountId, LocalDate from, LocalDate to, boolean bySymbol) {
        requireAccount(accountId);
        if (from != null && to != null && from.isAfter(to)) {
            throw new InvalidInputException("from must not be later than to");
        }

        Instant fromInstant = from != null ? from.atStartOfDay(ZoneOffset.UTC).toInstant() : Instant.EPOCH;
        Instant toInstant =
                to != null ? to.plusDays(1).atStartOfDay(ZoneOffset.UTC).toInstant() : clock.instant();

        List<RealisedPnlEntry> realisedEntries = pnlLedgerService.findRealisedPnl(accountId, fromInstant, toInstant);
        BigDecimal realisedPnl =
                realisedEntries.stream().map(RealisedPnlEntry::getRealisedPnl).reduce(BigDecimal.ZERO, BigDecimal::add);

        List<PricedHolding> holdings = priceHoldings(accountId, null);
        requirePricingUnlessEmpty(holdings);
        BigDecimal unrealisedPnl = holdings.stream()
                .filter(h -> h.priced() && h.convertible())
                .map(PricedHolding::marketValueInBaseCurrency)
                .reduce(BigDecimal.ZERO, BigDecimal::add)
                .subtract(holdings.stream()
                        .filter(h -> h.priced() && h.convertible())
                        .map(PricedHolding::costBasisInBaseCurrency)
                        .reduce(BigDecimal.ZERO, BigDecimal::add));

        BigDecimal totalPnl = realisedPnl.add(unrealisedPnl);

        List<SymbolPnl> bySymbolList = null;
        if (bySymbol) {
            bySymbolList = buildBySymbol(realisedEntries, holdings);
        }

        return new PnlResponse(
                accountId,
                portfolioProperties.baseCurrency(),
                from,
                to,
                realisedPnl,
                unrealisedPnl,
                totalPnl,
                bySymbolList,
                clock.instant());
    }

    private List<SymbolPnl> buildBySymbol(List<RealisedPnlEntry> realisedEntries, List<PricedHolding> holdings) {
        Map<String, BigDecimal> realisedBySymbol = new TreeMap<>();
        for (RealisedPnlEntry entry : realisedEntries) {
            realisedBySymbol.merge(entry.getSymbol(), entry.getRealisedPnl(), BigDecimal::add);
        }

        Map<String, BigDecimal> unrealisedBySymbol = new TreeMap<>();
        for (PricedHolding holding : holdings) {
            if (holding.priced() && holding.convertible()) {
                unrealisedBySymbol.put(holding.symbol(), holding.marketValueInBaseCurrency().subtract(holding.costBasisInBaseCurrency()));
            }
        }

        Set<String> symbols = new java.util.TreeSet<>();
        symbols.addAll(realisedBySymbol.keySet());
        symbols.addAll(unrealisedBySymbol.keySet());

        List<SymbolPnl> result = new java.util.ArrayList<>();
        for (String symbol : symbols) {
            BigDecimal realised = realisedBySymbol.getOrDefault(symbol, BigDecimal.ZERO);
            BigDecimal unrealised = unrealisedBySymbol.getOrDefault(symbol, BigDecimal.ZERO);
            result.add(new SymbolPnl(symbol, realised, unrealised, realised.add(unrealised)));
        }
        return result;
    }

    private BigDecimal totalRealisedPnl(long accountId) {
        return pnlLedgerService.findRealisedPnl(accountId, Instant.EPOCH, clock.instant()).stream()
                .map(RealisedPnlEntry::getRealisedPnl)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    private AccountEntity requireAccount(long accountId) {
        return accountRepository.findById(accountId).orElseThrow(() -> new AccountNotFoundException(accountId));
    }

    private void requirePricingUnlessEmpty(List<PricedHolding> holdings) {
        if (!holdings.isEmpty() && holdings.stream().noneMatch(PricedHolding::priced)) {
            throw new PricingUnavailableException();
        }
    }

    private List<PricedHolding> priceHoldings(long accountId, String symbolFilter) {
        List<PositionEntity> positions = symbolFilter != null
                ? positionRepository.findByAccountIdAndSymbolAndQuantityGreaterThan(accountId, symbolFilter, 0)
                : positionRepository.findByAccountIdAndQuantityGreaterThan(accountId, 0);

        if (positions.isEmpty()) {
            return List.of();
        }

        List<String> symbols = positions.stream().map(PositionEntity::getSymbol).toList();
        Map<String, InstrumentEntity> instrumentsBySymbol = new LinkedHashMap<>();
        for (InstrumentEntity instrument : instrumentRepository.findBySymbolIn(symbols)) {
            instrumentsBySymbol.put(instrument.getSymbol(), instrument);
        }

        Map<String, Quote> quotes = quoteCache.getQuotes(Set.copyOf(symbols));
        String baseCurrency = portfolioProperties.baseCurrency();

        return positions.stream().map(position -> priceOne(position, instrumentsBySymbol, quotes, baseCurrency)).toList();
    }

    private PricedHolding priceOne(
            PositionEntity position,
            Map<String, InstrumentEntity> instrumentsBySymbol,
            Map<String, Quote> quotes,
            String baseCurrency) {
        InstrumentEntity instrument = instrumentsBySymbol.get(position.getSymbol());
        String currency = instrument != null ? instrument.getCurrency() : baseCurrency;

        int quantity = position.getQuantity();
        BigDecimal averageCost = position.getAverageCost();
        BigDecimal costBasis = PnlCalculator.costBasis(quantity, averageCost);

        Quote quote = quotes.get(position.getSymbol());
        boolean priced = quote != null;

        BigDecimal lastPrice = priced ? quote.price() : null;
        BigDecimal marketValue = priced ? PnlCalculator.marketValue(quantity, lastPrice) : null;
        BigDecimal unrealisedPnl = priced ? PnlCalculator.unrealisedPnl(marketValue, costBasis) : null;
        BigDecimal unrealisedPnlPercent = priced ? PnlCalculator.unrealisedPnlPercent(unrealisedPnl, costBasis) : null;
        Instant priceAsOf = priced ? quote.asOf() : null;
        boolean stale = !priced || quote.stale();

        BigDecimal costBasisInBase = currencyConverter.convert(costBasis, currency, baseCurrency).orElse(null);
        BigDecimal marketValueInBase =
                priced ? currencyConverter.convert(marketValue, currency, baseCurrency).orElse(null) : null;
        boolean convertible = costBasisInBase != null && (!priced || marketValueInBase != null);

        return new PricedHolding(
                position.getSymbol(),
                quantity,
                averageCost,
                costBasis,
                lastPrice,
                marketValue,
                unrealisedPnl,
                unrealisedPnlPercent,
                currency,
                priceAsOf,
                stale,
                priced,
                costBasisInBase,
                marketValueInBase,
                convertible);
    }
}

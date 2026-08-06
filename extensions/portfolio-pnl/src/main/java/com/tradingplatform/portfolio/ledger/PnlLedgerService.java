package com.tradingplatform.portfolio.ledger;

import com.tradingplatform.portfolio.kafka.TradeEventPayload;
import com.tradingplatform.portfolio.pnl.PnlCalculator;
import com.tradingplatform.portfolio.repository.RealisedPnlRepository;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Keeps the realised profit-and-loss ledger current from {@code trade-events}. Booking
 * happens only on {@code ORDER_FILLED} events with {@code side = SELL}: a buy changes
 * average cost but books nothing, and a reject or cancel has no profit-and-loss effect
 * by definition.
 */
@Service
public class PnlLedgerService {

    private static final Logger log = LoggerFactory.getLogger(PnlLedgerService.class);

    private final RealisedPnlRepository repository;

    public PnlLedgerService(RealisedPnlRepository repository) {
        this.repository = repository;
    }

    /**
     * Books realised profit and loss for one SELL fill. Idempotent on {@code eventId}:
     * a duplicate delivery of the same event hits the primary key on
     * {@code portfolio_realised_pnl} and is treated as already handled, per mechanism
     * 1 in docs/contracts/kafka-topics.md.
     */
    @Transactional
    public void recordSaleIfNew(UUID eventId, TradeEventPayload payload) {
        if (repository.existsById(eventId)) {
            log.debug("Event {} already booked, skipping", eventId);
            return;
        }

        BigDecimalArgumentsGuard.requireNonNull(payload.executedPrice(), "executedPrice");
        BigDecimalArgumentsGuard.requireNonNull(payload.averageCostAfter(), "averageCostAfter");

        var realisedPnl =
                PnlCalculator.realisedPnlOnSale(payload.executedPrice(), payload.averageCostAfter(), payload.quantity());

        RealisedPnlEntry entry = new RealisedPnlEntry(
                eventId,
                payload.orderId(),
                payload.accountId(),
                payload.symbol(),
                payload.quantity(),
                payload.executedPrice(),
                payload.averageCostAfter(),
                realisedPnl,
                payload.executedOn() != null ? payload.executedOn() : Instant.now());

        try {
            repository.save(entry);
        } catch (DataIntegrityViolationException e) {
            // Two consumer threads (or a retry racing a prior attempt's commit) both
            // passed the existsById check. The unique primary key on event_id is the
            // real guard; losing this race is the expected, safe outcome.
            log.debug("Event {} booked concurrently, ignoring duplicate insert", eventId);
        }
    }

    public List<RealisedPnlEntry> findRealisedPnl(long accountId, Instant from, Instant to) {
        return repository.findByAccountIdAndExecutedOnBetween(accountId, from, to);
    }

    private static final class BigDecimalArgumentsGuard {
        static void requireNonNull(Object value, String field) {
            if (value == null) {
                throw new IllegalArgumentException("SELL fill event missing required field: " + field);
            }
        }
    }
}

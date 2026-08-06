package com.tradingplatform.portfolio.repository;

import com.tradingplatform.portfolio.ledger.RealisedPnlEntry;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface RealisedPnlRepository extends JpaRepository<RealisedPnlEntry, UUID> {

    List<RealisedPnlEntry> findByAccountIdAndExecutedOnBetween(Long accountId, Instant from, Instant to);
}

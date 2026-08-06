package com.tradingplatform.portfolio.repository;

import com.tradingplatform.portfolio.domain.PositionEntity;
import com.tradingplatform.portfolio.domain.PositionId;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PositionRepository extends JpaRepository<PositionEntity, PositionId> {

    /** Open holdings only. Positions with a net quantity of zero are excluded, per the contract. */
    List<PositionEntity> findByAccountIdAndQuantityGreaterThan(Long accountId, int quantity);

    List<PositionEntity> findByAccountIdAndSymbolAndQuantityGreaterThan(Long accountId, String symbol, int quantity);
}

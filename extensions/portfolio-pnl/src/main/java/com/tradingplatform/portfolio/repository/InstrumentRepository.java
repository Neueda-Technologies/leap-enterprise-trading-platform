package com.tradingplatform.portfolio.repository;

import com.tradingplatform.portfolio.domain.InstrumentEntity;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface InstrumentRepository extends JpaRepository<InstrumentEntity, String> {

    List<InstrumentEntity> findBySymbolIn(List<String> symbols);
}

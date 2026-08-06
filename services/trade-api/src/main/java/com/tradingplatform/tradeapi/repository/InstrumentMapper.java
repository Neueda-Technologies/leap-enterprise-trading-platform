package com.tradingplatform.tradeapi.repository;

import com.tradingplatform.domain.model.Instrument;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * Reads {@code instruments}. Reference data, never written by this service.
 */
@Mapper
public interface InstrumentMapper {

    /**
     * Loads an instrument by its symbol, whether or not it is tradable.
     *
     * <p>The query does not filter on {@code tradable}. The domain decides what an untradable
     * instrument means, and it happens to give the same answer as a missing one. Filtering here would
     * move business rule 3 into a mapper, where it cannot be tested without a database and where the
     * next reader has no reason to look for it.
     *
     * @return the instrument, or null when no row exists
     */
    Instrument findBySymbol(@Param("symbol") String symbol);
}

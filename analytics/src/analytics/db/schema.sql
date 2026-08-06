-- =============================================================================
-- Runtime DDL applied to the DuckDB warehouse file.
--
-- The four CREATE TABLE statements for dim_date, dim_instrument, dim_account
-- and fact_trades mirror docs/contracts/analytics-schema.sql exactly: same
-- columns, same types, same keys. That file is the contract; this one is
-- what the ETL runs at startup so the warehouse file can be created from
-- nothing. Indexes are enabled here because DuckDB benefits from them on the
-- foreign keys, per the contract's own note.
--
-- Two tables below are not part of the contract and are marked as such:
-- etl_watermark and etl_quarantine. Both are pipeline plumbing, not part of
-- the star schema an analyst queries.
-- =============================================================================

CREATE TABLE IF NOT EXISTS dim_account (
    account_key     BIGINT       NOT NULL,
    account_id      VARCHAR(32)  NOT NULL,
    holder_name     VARCHAR(255) NOT NULL,
    status          VARCHAR(20)  NOT NULL,
    effective_date  DATE         NOT NULL,
    end_date        DATE,
    is_current      BOOLEAN      NOT NULL,
    source_id       BIGINT       NOT NULL,
    loaded_at       TIMESTAMP    NOT NULL,

    CONSTRAINT pk_dim_account PRIMARY KEY (account_key)
);

CREATE TABLE IF NOT EXISTS dim_instrument (
    instrument_key  BIGINT       NOT NULL,
    symbol          VARCHAR(20)  NOT NULL,
    name            VARCHAR(255) NOT NULL,
    asset_class     VARCHAR(20)  NOT NULL,
    currency        CHAR(3)      NOT NULL,
    exchange        VARCHAR(20),
    tradable        BOOLEAN      NOT NULL,
    loaded_at       TIMESTAMP    NOT NULL,

    CONSTRAINT pk_dim_instrument PRIMARY KEY (instrument_key),
    CONSTRAINT uq_dim_instrument_symbol UNIQUE (symbol)
);

CREATE TABLE IF NOT EXISTS dim_date (
    date_key    INTEGER     NOT NULL,
    full_date   DATE        NOT NULL,
    day         INTEGER     NOT NULL,
    month       INTEGER     NOT NULL,
    year        INTEGER     NOT NULL,
    quarter     INTEGER     NOT NULL,
    day_of_week INTEGER     NOT NULL,
    day_name    VARCHAR(9)  NOT NULL,
    month_name  VARCHAR(9)  NOT NULL,
    is_weekday  BOOLEAN     NOT NULL,

    CONSTRAINT pk_dim_date PRIMARY KEY (date_key),
    CONSTRAINT uq_dim_date_full_date UNIQUE (full_date)
);

CREATE TABLE IF NOT EXISTS fact_trades (
    trade_key       BIGINT        NOT NULL,
    account_key     BIGINT        NOT NULL,
    instrument_key  BIGINT        NOT NULL,
    date_key        INTEGER       NOT NULL,
    side            VARCHAR(4)    NOT NULL,
    quantity        INTEGER       NOT NULL,
    price           DECIMAL(18,2) NOT NULL,
    status          VARCHAR(20)   NOT NULL,
    executed_price  DECIMAL(18,2),
    trade_value     DECIMAL(18,2) NOT NULL,
    source_order_id VARCHAR(36)   NOT NULL,
    created_at      TIMESTAMP     NOT NULL,
    loaded_at       TIMESTAMP     NOT NULL,

    CONSTRAINT pk_fact_trades PRIMARY KEY (trade_key),
    CONSTRAINT uq_fact_trades_source UNIQUE (source_order_id),
    CONSTRAINT fk_fact_trades_account
        FOREIGN KEY (account_key)    REFERENCES dim_account (account_key),
    CONSTRAINT fk_fact_trades_instrument
        FOREIGN KEY (instrument_key) REFERENCES dim_instrument (instrument_key),
    CONSTRAINT fk_fact_trades_date
        FOREIGN KEY (date_key)       REFERENCES dim_date (date_key)
);

CREATE INDEX IF NOT EXISTS ix_fact_trades_date       ON fact_trades (date_key);
CREATE INDEX IF NOT EXISTS ix_fact_trades_account    ON fact_trades (account_key);
CREATE INDEX IF NOT EXISTS ix_fact_trades_instrument ON fact_trades (instrument_key);
CREATE INDEX IF NOT EXISTS ix_dim_account_current    ON dim_account (account_id, is_current);

-- -----------------------------------------------------------------------------
-- Addition, not part of docs/contracts/analytics-schema.sql.
-- Tracks the incremental watermark per pipeline stage so that `etl run` only
-- extracts orders created since the last successful load. One row per
-- pipeline name.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS etl_watermark (
    pipeline_name   VARCHAR(64) NOT NULL,
    last_loaded_at  TIMESTAMP   NOT NULL,

    CONSTRAINT pk_etl_watermark PRIMARY KEY (pipeline_name)
);

-- -----------------------------------------------------------------------------
-- Addition, not part of docs/contracts/analytics-schema.sql.
-- Rows that failed a pre-load validation check land here instead of
-- fact_trades, per the dead-letter principle in docs/contracts/kafka-topics.md
-- applied to the batch side: a bad row is quarantined and reported, not
-- silently dropped and not allowed to fail the whole batch.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS etl_quarantine (
    quarantine_id   BIGINT      NOT NULL,
    source_order_id VARCHAR(36),
    stage           VARCHAR(32) NOT NULL,
    reason          VARCHAR(255) NOT NULL,
    raw_payload     VARCHAR,
    quarantined_at  TIMESTAMP   NOT NULL,

    CONSTRAINT pk_etl_quarantine PRIMARY KEY (quarantine_id)
);

-- -----------------------------------------------------------------------------
-- Addition, not part of docs/contracts/analytics-schema.sql.
-- Cache of Fauxnance EOD candles pulled during extract. Staging only: it
-- exists so the reasonableness check in etl.validate (an executed price
-- should fall within the day's traded range) has something to check against,
-- and so a re-run does not re-request a symbol and date range already held.
-- Nothing in the dashboard queries this table; it is not part of the star
-- schema an analyst reads.
-- -----------------------------------------------------------------------------
-- -----------------------------------------------------------------------------
-- Addition, not part of docs/contracts/analytics-schema.sql.
-- The Sprint 7 kafka_sink's idempotency guard: a processed-events table
-- keyed on eventId, per the first mechanism documented under "Idempotent
-- handling" in docs/contracts/kafka-topics.md. A duplicate delivery of the
-- same eventId is recognised here and skipped before it can touch
-- fact_trades a second time.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS kafka_processed_events (
    event_id      VARCHAR(64) NOT NULL,
    topic         VARCHAR(64) NOT NULL,
    processed_at  TIMESTAMP   NOT NULL,

    CONSTRAINT pk_kafka_processed_events PRIMARY KEY (event_id)
);

CREATE TABLE IF NOT EXISTS stg_market_candles (
    symbol      VARCHAR(20) NOT NULL,
    trade_date  DATE        NOT NULL,
    open        DECIMAL(18,4),
    high        DECIMAL(18,4),
    low         DECIMAL(18,4),
    close       DECIMAL(18,4),
    volume      BIGINT,
    fetched_at  TIMESTAMP   NOT NULL,

    CONSTRAINT pk_stg_market_candles PRIMARY KEY (symbol, trade_date)
);

-- =============================================================================
-- Portfolio and P&L extension: extension-owned tables.
--
-- Everything else this service reads (accounts, instruments, positions) is
-- owned by the Trade REST API team and defined in
-- docs/contracts/database-schema.sql. This service never issues DDL against
-- those tables and connects with a read-only role in a deployed environment.
--
-- The one table below belongs to this extension. It is the realised
-- profit-and-loss ledger, built by consuming trade-events rather than by
-- querying orders, per the instructions in portfolio-api.yaml: "Realised
-- profit and loss | Computed from the sell orders in orders, or accumulated
-- from trade-events". This reference implementation takes the second option
-- because the trade-events payload already carries everything a SELL fill
-- needs to book realised profit and loss (executedPrice, quantity and
-- averageCostAfter), so no second read path into the trading database is
-- needed.
--
-- Idempotency: event_id is the primary key. A duplicate delivery of the same
-- trade-events message is a duplicate insert, rejected by the primary key,
-- and treated as "already handled". This is mechanism 1 from
-- docs/contracts/kafka-topics.md.
-- =============================================================================

CREATE TABLE IF NOT EXISTS portfolio_realised_pnl (
    event_id             UUID          NOT NULL,
    order_id             UUID          NOT NULL,
    account_id           BIGINT        NOT NULL,
    symbol               VARCHAR(20)   NOT NULL,
    quantity             INT           NOT NULL,
    executed_price       NUMERIC(18,2) NOT NULL,
    average_cost_at_sale NUMERIC(18,2) NOT NULL,
    realised_pnl         NUMERIC(18,2) NOT NULL,
    executed_on          TIMESTAMP     NOT NULL,
    recorded_on          TIMESTAMP     NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_portfolio_realised_pnl PRIMARY KEY (event_id)
);

COMMENT ON TABLE portfolio_realised_pnl IS
    'Realised profit and loss booked from ORDER_FILLED SELL events on trade-events. Append-only: a booked row is never updated, matching the "once booked it never changes" rule in portfolio-api.yaml.';
COMMENT ON COLUMN portfolio_realised_pnl.event_id IS
    'The eventId from the trade-events envelope. Primary key, so a replayed event is a no-op.';
COMMENT ON COLUMN portfolio_realised_pnl.average_cost_at_sale IS
    'Taken from averageCostAfter on the SELL event. A sell leaves average cost unchanged (see positions.average_cost in database-schema.sql), so the average cost after the sell equals the average cost at the moment of sale.';
COMMENT ON COLUMN portfolio_realised_pnl.realised_pnl IS
    '(executed_price - average_cost_at_sale) * quantity, booked once and never recomputed from a later price.';

CREATE INDEX IF NOT EXISTS ix_portfolio_realised_pnl_account_executed
    ON portfolio_realised_pnl (account_id, executed_on);

CREATE INDEX IF NOT EXISTS ix_portfolio_realised_pnl_account_symbol
    ON portfolio_realised_pnl (account_id, symbol);

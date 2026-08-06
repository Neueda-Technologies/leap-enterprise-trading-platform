-- =============================================================================
-- Enterprise Trading Platform: operational schema, executable form
-- =============================================================================
--
-- Source: docs/contracts/database-schema.sql. That file is the binding
-- contract and carries the full rationale for every table, type and
-- constraint. This file is the same DDL, unaltered in substance, arranged to
-- run unattended as a Postgres init script.
--
-- Mounted into the postgres container at /docker-entrypoint-initdb.d and
-- executed once, in filename order, the first time the container starts
-- against an empty data volume. It does not run again against a volume that
-- already has data. To rerun it, drop the volume first: see infra/README.md.
--
-- Do not edit the shape of a table here without also updating
-- docs/contracts/database-schema.sql. This file is a rendering of that
-- contract, not a second source of truth for it.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- INSTRUMENTS
-- Tradable securities. The reference data every order is validated against.
-- -----------------------------------------------------------------------------
CREATE TABLE instruments (
    symbol       VARCHAR(20)  NOT NULL,
    name         VARCHAR(255) NOT NULL,
    asset_class  VARCHAR(20)  NOT NULL,
    currency     CHAR(3)      NOT NULL,
    tradable     BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_instruments PRIMARY KEY (symbol),

    CONSTRAINT ck_instruments_asset_class
        CHECK (asset_class IN ('EQUITY', 'ETF', 'FX', 'CRYPTO', 'BOND')),
    CONSTRAINT ck_instruments_currency
        CHECK (currency ~ '^[A-Z]{3}$')
);

COMMENT ON TABLE  instruments IS 'Tradable instruments. Reference data, rarely written.';
COMMENT ON COLUMN instruments.symbol IS
    'Fauxnance symbol scheme: plain ticker for US equity and ETF, .NS or .BO suffix for NSE or BSE, FX: prefix for a currency pair, X: prefix for crypto.';
COMMENT ON COLUMN instruments.tradable IS
    'FALSE suspends trading in the instrument without deleting it. Deleting an instrument would orphan the order history, which is the audit trail.';


-- -----------------------------------------------------------------------------
-- ACCOUNTS
-- Trading accounts and their cash balances. The row that order placement locks.
-- -----------------------------------------------------------------------------
CREATE TABLE accounts (
    id            BIGINT        GENERATED ALWAYS AS IDENTITY,
    account_id    VARCHAR(32)   NOT NULL,
    holder_name   VARCHAR(255)  NOT NULL,
    cash_balance  NUMERIC(18,2) NOT NULL,
    status        VARCHAR(20)   NOT NULL,
    version       INT           NOT NULL DEFAULT 0,
    last_updated  TIMESTAMP     NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_accounts PRIMARY KEY (id),
    CONSTRAINT uq_accounts_account_id UNIQUE (account_id),

    CONSTRAINT ck_accounts_status
        CHECK (status IN ('ACTIVE', 'SUSPENDED', 'CLOSED')),
    CONSTRAINT ck_accounts_cash_balance_non_negative
        CHECK (cash_balance >= 0)
);

COMMENT ON TABLE  accounts IS 'Trading accounts and cash balances.';
COMMENT ON COLUMN accounts.id IS
    'Surrogate primary key. This is what "accountId" means in the REST API, in the JWT claim, in Kafka message payloads, and in orders.account_id and positions.account_id.';
COMMENT ON COLUMN accounts.account_id IS
    'Business account reference shown to customers, for example ACC-1001. Not a foreign key target.';
COMMENT ON COLUMN accounts.version IS
    'Optimistic lock. Every write increments it and updates with WHERE version = :expected. Zero rows affected means another transaction won, and the caller retries. Non-functional requirement NFR-02.';
COMMENT ON COLUMN accounts.cash_balance IS
    'Available cash. The non-negative check is a last line of defence, not the business rule: rule 6 rejects an unaffordable buy before the write. A constraint violation reaching the application means the rule was skipped.';


-- -----------------------------------------------------------------------------
-- ORDERS
-- Every order ever placed, in any status. The audit trail: nothing is deleted
-- and a rejected order is stored, not discarded.
-- -----------------------------------------------------------------------------
CREATE TABLE orders (
    id               UUID          NOT NULL,
    account_id       BIGINT        NOT NULL,
    symbol           VARCHAR(20)   NOT NULL,
    side             VARCHAR(4)    NOT NULL,
    quantity         INT           NOT NULL,
    price            NUMERIC(18,2) NOT NULL,
    status           VARCHAR(20)   NOT NULL,
    idempotency_key  VARCHAR(100)  NOT NULL,
    created_on       TIMESTAMP     NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_orders PRIMARY KEY (id),
    CONSTRAINT fk_orders_account
        FOREIGN KEY (account_id) REFERENCES accounts (id),
    CONSTRAINT fk_orders_instrument
        FOREIGN KEY (symbol) REFERENCES instruments (symbol),
    CONSTRAINT uq_orders_idempotency_key UNIQUE (idempotency_key),

    CONSTRAINT ck_orders_side
        CHECK (side IN ('BUY', 'SELL')),
    CONSTRAINT ck_orders_status
        CHECK (status IN ('NEW', 'FILLED', 'REJECTED', 'CANCELLED')),
    CONSTRAINT ck_orders_quantity_positive
        CHECK (quantity > 0),
    CONSTRAINT ck_orders_price_positive
        CHECK (price > 0)
);

COMMENT ON TABLE  orders IS 'Placed and executed orders. The audit trail. Append-only in practice: rows are updated to a terminal status, never removed.';
COMMENT ON COLUMN orders.account_id IS
    'References accounts.id, the numeric surrogate key, not accounts.account_id.';
COMMENT ON COLUMN orders.idempotency_key IS
    'Client-generated request identifier. The unique constraint IS the duplicate-order check, business rule 8. Do not implement the rule as a SELECT followed by an INSERT: two concurrent requests both pass the SELECT.';
COMMENT ON COLUMN orders.status IS
    'NEW is the working state. FILLED, REJECTED and CANCELLED are terminal. There is no partial-fill state, so the Trade Executor fills in full or rejects.';
COMMENT ON COLUMN orders.price IS
    'The limit price submitted by the client. The price actually achieved is executed_price.';


-- -----------------------------------------------------------------------------
-- POSITIONS
-- Net holding per account and instrument.
-- -----------------------------------------------------------------------------
CREATE TABLE positions (
    account_id    BIGINT        NOT NULL,
    symbol        VARCHAR(20)   NOT NULL,
    quantity      INT           NOT NULL,
    average_cost  NUMERIC(18,2) NOT NULL,

    CONSTRAINT pk_positions PRIMARY KEY (account_id, symbol),
    CONSTRAINT fk_positions_account
        FOREIGN KEY (account_id) REFERENCES accounts (id),
    CONSTRAINT fk_positions_instrument
        FOREIGN KEY (symbol) REFERENCES instruments (symbol),

    CONSTRAINT ck_positions_quantity_non_negative
        CHECK (quantity >= 0),
    CONSTRAINT ck_positions_average_cost_non_negative
        CHECK (average_cost >= 0)
);

COMMENT ON TABLE  positions IS 'Current net holdings. Derived state: it can be rebuilt from the order history, and a team should prove that it can.';
COMMENT ON COLUMN positions.quantity IS
    'Net held quantity. Non-negative because short selling is out of scope. A sell that would take it below zero is rejected by business rule 7.';
COMMENT ON COLUMN positions.average_cost IS
    'Weighted average cost per unit. A buy recalculates it as (oldQty * oldAvg + newQty * fillPrice) / (oldQty + newQty). A sell reduces quantity and leaves it unchanged, which is what makes realised profit and loss computable at the point of sale.';


-- =============================================================================
-- SPRINT 7 ADDITIONS
-- Required once execution becomes asynchronous, because the price an order
-- was filled at stops being the price it was submitted at.
-- =============================================================================

ALTER TABLE orders
    ADD COLUMN executed_price NUMERIC(18,2),
    ADD COLUMN executed_on    TIMESTAMP,
    ADD COLUMN reject_reason  VARCHAR(64);

COMMENT ON COLUMN orders.executed_price IS
    'The Fauxnance quote the Trade Executor filled at. NULL until the order reaches FILLED.';
COMMENT ON COLUMN orders.reject_reason IS
    'Machine-readable cause on a REJECTED order, for example INSUFFICIENT_FUNDS or PRICE_NOT_MET. Mirrors the reason field on the trade-events message.';

ALTER TABLE orders
    ADD CONSTRAINT ck_orders_executed_price_positive
        CHECK (executed_price IS NULL OR executed_price > 0);


-- =============================================================================
-- INDEXES
-- Each one exists because a named query needs it.
-- =============================================================================

-- GET /api/v1/accounts/{id}/orders, newest first. The blotter's only query.
CREATE INDEX ix_orders_account_created
    ON orders (account_id, created_on DESC);

-- The Trade Executor's guarded transition, and any sweep for orders stuck in
-- NEW. Partial, because terminal orders are the overwhelming majority.
CREATE INDEX ix_orders_status_new
    ON orders (status)
    WHERE status = 'NEW';

-- Exposure by instrument, and instrument-level analytics.
CREATE INDEX ix_orders_symbol_created
    ON orders (symbol, created_on DESC);

-- The batch ETL extract: everything created since the last watermark.
CREATE INDEX ix_orders_created_on
    ON orders (created_on);

-- Portfolio valuation reads every position for one account. The composite
-- primary key already serves this, since account_id leads it. No index needed.

-- Aggregate holdings across accounts for one instrument, used by exposure
-- reporting and by the market-data poller when deciding which symbols to poll.
CREATE INDEX ix_positions_symbol
    ON positions (symbol);

-- The auth service resolves a login to an account by its business reference.
-- Served by uq_accounts_account_id. No index needed.

-- Instrument lookup by asset class, for the dashboard breakdown.
CREATE INDEX ix_instruments_asset_class
    ON instruments (asset_class)
    WHERE tradable = TRUE;


-- =============================================================================
-- LEAST-PRIVILEGE ROLES
-- Left commented, as in the source contract. Passwords come from the
-- environment, never from a committed file, so these are not enacted by the
-- init script. Create them by hand against a real deployment.
-- =============================================================================

-- CREATE ROLE trading_app LOGIN PASSWORD :'app_password';
-- GRANT CONNECT ON DATABASE trading TO trading_app;
-- GRANT USAGE ON SCHEMA public TO trading_app;
-- GRANT SELECT, INSERT, UPDATE ON accounts, orders, positions TO trading_app;
-- GRANT SELECT ON instruments TO trading_app;
-- No DELETE anywhere: the audit trail is not deletable by the application.
-- No DDL: schema changes go through migrations run as the owner.

-- CREATE ROLE analytics_reader LOGIN PASSWORD :'etl_password';
-- GRANT CONNECT ON DATABASE trading TO analytics_reader;
-- GRANT USAGE ON SCHEMA public TO analytics_reader;
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO analytics_reader;
-- The ETL extracts. It never writes to the operational store.

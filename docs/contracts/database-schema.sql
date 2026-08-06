-- =============================================================================
-- Enterprise Trading Platform: operational schema (PostgreSQL)
-- Instructor reference. Status: canonical shape, not a handout.
-- =============================================================================
--
-- WHY THIS FILE EXISTS
--
-- Participants design the trade database themselves in Sprint 3. They are not
-- given this file. The point of Sprint 3 is the modelling: identifying entities,
-- normalising to third normal form, choosing keys, and defending the result in
-- a walkthrough. Handing over finished DDL removes the assessment.
--
-- This file is what a correct answer converges on. Use it three ways:
--   1. As the marking reference for the Sprint 3 assessment.
--   2. As the shape every later sprint is built against. The Sprint 5 domain
--      model, the Sprint 6 MyBatis mappers, and contracts/trade-api.yaml all
--      assume these column names and types.
--   3. As the reconciliation point at the end of Sprint 3. A team whose schema
--      differs in substance, rather than in naming, converges before Sprint 5.
--
-- SOURCE
--
-- Tables, columns, types and constraints follow the project specification,
-- section 18.1, without alteration. Indexes, check constraints, the positions
-- primary key and the Sprint 7 additions are supplied here because the
-- specification stops short of them. Each addition is marked.
--
-- A NAMING COLLISION YOU MUST UNDERSTAND BEFORE READING THE DDL
--
-- ACCOUNTS has two identifier columns:
--   accounts.id         BIGINT       the surrogate primary key
--   accounts.account_id VARCHAR(32)  the business account reference
--
-- ORDERS.account_id and POSITIONS.account_id are BIGINT and reference
-- accounts.id, NOT accounts.account_id, despite the shared name. The
-- specification defines it this way and the API contract follows it: the name
-- "accountId" means the numeric key everywhere except in AccountResponse.
-- See docs/DECISIONS.md. Do not silently rename the column to fix the
-- confusion; downstream contracts depend on it.
--
-- CONVENTIONS
--
--   Money      NUMERIC(18,2). Never float or double precision. A binary
--              floating-point cash balance cannot represent 0.10 exactly and
--              will drift over a few thousand trades.
--   Time       TIMESTAMP as specified. Prefer TIMESTAMPTZ in any schema you
--              design yourself; a trading system spanning Dublin, Boston and
--              Bangalore has no single local time.
--   Enums      Held as VARCHAR with a CHECK constraint rather than a Postgres
--              ENUM type. Adding a value to a native enum needs DDL, and
--              MyBatis maps a VARCHAR to a Java enum without a type handler.
--   Casing     snake_case in SQL, camelCase in JSON. The mapping happens in the
--              MyBatis result map, in one place.
--
-- APPLYING IT
--
--   psql -h localhost -U postgres -d trading -f database-schema.sql
--
-- Run it as a migration file under version control, numbered and immutable,
-- never as an ad hoc script against a running database.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- INSTRUMENTS
-- Tradable securities. The reference data every order is validated against.
-- Symbol is the natural key: it is externally assigned, stable, and already the
-- value carried on every order and every Fauxnance request, so a surrogate key
-- would add a join without adding anything.
-- Specification: section 18.1, "INSTRUMENTS / POSITIONS Tables".
-- -----------------------------------------------------------------------------
CREATE TABLE instruments (
    symbol       VARCHAR(20)  NOT NULL,
    name         VARCHAR(255) NOT NULL,
    asset_class  VARCHAR(20)  NOT NULL,
    currency     CHAR(3)      NOT NULL,
    tradable     BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_instruments PRIMARY KEY (symbol),

    -- Added here, not in the specification.
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
-- Specification: section 18.1, "ACCOUNTS Table".
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

    -- Added here, not in the specification.
    CONSTRAINT ck_accounts_status
        CHECK (status IN ('ACTIVE', 'SUSPENDED', 'CLOSED')),
    CONSTRAINT ck_accounts_cash_balance_non_negative
        CHECK (cash_balance >= 0)
);

COMMENT ON TABLE  accounts IS 'Trading accounts and cash balances.';
COMMENT ON COLUMN accounts.id IS
    'Surrogate primary key. This is what "accountId" means in the REST API, in the JWT claim, in Kafka message payloads, and in orders.account_id and positions.account_id.';
COMMENT ON COLUMN accounts.account_id IS
    'Business account reference shown to customers, for example ACC-000001. Not a foreign key target.';
COMMENT ON COLUMN accounts.version IS
    'Optimistic lock. Every write increments it and updates with WHERE version = :expected. Zero rows affected means another transaction won, and the caller retries. This is non-functional requirement NFR-02.';
COMMENT ON COLUMN accounts.cash_balance IS
    'Available cash. The non-negative check is a last line of defence, not the business rule: rule 6 rejects an unaffordable buy before the write. A constraint violation reaching the application means the rule was skipped.';


-- -----------------------------------------------------------------------------
-- ORDERS
-- Every order ever placed, in any status. This table is the audit trail, so
-- nothing is ever deleted from it and a rejected order is stored, not discarded.
-- Specification: section 18.1, "ORDERS Table".
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

    -- Added here, not in the specification. These encode business rules 4 and 5
    -- at the storage layer so that a bug in the service cannot persist an
    -- impossible order.
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
-- Specification: section 18.1, "INSTRUMENTS / POSITIONS Tables".
-- The composite primary key is added here: the specification lists the columns
-- but not the key, and an account can hold each instrument exactly once.
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

    -- Added here, not in the specification.
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
-- Not in the specification. Required once execution becomes asynchronous,
-- because the price an order was filled at stops being the price it was
-- submitted at. Add these as a separate numbered migration in Sprint 7, not by
-- editing the Sprint 3 migration.
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
-- Not in the specification. Each one exists because a named query needs it. Do
-- not add an index without being able to name the query it serves: every index
-- is paid for on every write, and orders is a write-heavy table.
-- =============================================================================

-- GET /api/v1/accounts/{id}/orders, newest first. The blotter's only query, run
-- on every dashboard load.
CREATE INDEX ix_orders_account_created
    ON orders (account_id, created_on DESC);

-- The Trade Executor's guarded transition, and any sweep for orders stuck in
-- NEW. Partial, because terminal orders are the overwhelming majority of the
-- table and are never selected by status alone.
CREATE INDEX ix_orders_status_new
    ON orders (status)
    WHERE status = 'NEW';

-- Exposure by instrument, and the instrument-level analytics in Sprint 4.
CREATE INDEX ix_orders_symbol_created
    ON orders (symbol, created_on DESC);

-- The batch ETL extract in Sprint 7: everything created since the last
-- watermark.
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

-- Instrument lookup by asset class, for the Sprint 4 dashboard breakdown.
CREATE INDEX ix_instruments_asset_class
    ON instruments (asset_class)
    WHERE tradable = TRUE;


-- =============================================================================
-- LEAST-PRIVILEGE ROLES
-- Not in the specification. Sprint 3 teaches least privilege and Sprint 6
-- connects a service to this schema; the application must not connect as the
-- owner. Passwords come from the environment, never from a committed file.
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


-- =============================================================================
-- SEED DATA
-- Not in the specification. Sprint 3 requires representative seed data. Keep it
-- in a separate file so that the schema migration and the fixture data can be
-- applied independently. The set must cover, at minimum:
--
--   - one ACTIVE account with cash, for the happy path
--   - one SUSPENDED and one CLOSED account, to exercise ACC-403
--   - one account with a near-zero balance, to exercise ORD-400
--   - one account holding a position, to exercise a sell and ORD-409
--   - at least one non-tradable instrument, to exercise INS-404
--   - instruments from more than one currency and more than one venue, using
--     real Fauxnance symbols so that quotes resolve: AAPL, SPY, INFY.NS,
--     RELIANCE.NS, FX:EURUSD, X:BTC-USD
--
-- A seed set that only contains the happy path lets a whole error catalogue go
-- untested.
-- =============================================================================

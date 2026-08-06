-- H2 rendering of docs/contracts/database-schema.sql, for the mapper tests.
--
-- It is not the schema. The operational schema is Postgres and lives in the Sprint 3 migration.
-- This file exists so that the mapper SQL can be exercised in a few hundred milliseconds without a
-- container, and it keeps every constraint the mappers rely on: the unique idempotency key that is
-- business rule 8, the composite position key that the upsert resolves against, and the status
-- check constraints.
--
-- What it deliberately drops, because H2 does not have them and no mapper depends on them: the
-- regular expression check on currency, the partial indexes, and the least-privilege roles. A test
-- that passes here and fails against Postgres is possible, which is why the compose stack is the
-- acceptance environment and this is only the fast feedback loop.

DROP ALL OBJECTS;

CREATE TABLE instruments (
    symbol       VARCHAR(20)  NOT NULL,
    name         VARCHAR(255) NOT NULL,
    asset_class  VARCHAR(20)  NOT NULL,
    currency     CHAR(3)      NOT NULL,
    tradable     BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_instruments PRIMARY KEY (symbol),
    CONSTRAINT ck_instruments_asset_class
        CHECK (asset_class IN ('EQUITY', 'ETF', 'FX', 'CRYPTO', 'BOND'))
);

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
    CONSTRAINT ck_accounts_status CHECK (status IN ('ACTIVE', 'SUSPENDED', 'CLOSED')),
    CONSTRAINT ck_accounts_cash_balance_non_negative CHECK (cash_balance >= 0)
);

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
    executed_price   NUMERIC(18,2),
    executed_on      TIMESTAMP,
    reject_reason    VARCHAR(64),

    CONSTRAINT pk_orders PRIMARY KEY (id),
    CONSTRAINT fk_orders_account FOREIGN KEY (account_id) REFERENCES accounts (id),
    CONSTRAINT fk_orders_instrument FOREIGN KEY (symbol) REFERENCES instruments (symbol),
    CONSTRAINT uq_orders_idempotency_key UNIQUE (idempotency_key),
    CONSTRAINT ck_orders_side CHECK (side IN ('BUY', 'SELL')),
    CONSTRAINT ck_orders_status CHECK (status IN ('NEW', 'FILLED', 'REJECTED', 'CANCELLED')),
    CONSTRAINT ck_orders_quantity_positive CHECK (quantity > 0),
    CONSTRAINT ck_orders_price_positive CHECK (price > 0)
);

CREATE TABLE positions (
    account_id    BIGINT        NOT NULL,
    symbol        VARCHAR(20)   NOT NULL,
    quantity      INT           NOT NULL,
    average_cost  NUMERIC(18,2) NOT NULL,

    CONSTRAINT pk_positions PRIMARY KEY (account_id, symbol),
    CONSTRAINT fk_positions_account FOREIGN KEY (account_id) REFERENCES accounts (id),
    CONSTRAINT fk_positions_instrument FOREIGN KEY (symbol) REFERENCES instruments (symbol),
    CONSTRAINT ck_positions_quantity_non_negative CHECK (quantity >= 0),
    CONSTRAINT ck_positions_average_cost_non_negative CHECK (average_cost >= 0)
);

-- Fixtures. The set covers every path the error catalogue has: an active account with cash, a
-- suspended one, an account holding a position, and an instrument that is not tradable.
INSERT INTO instruments (symbol, name, asset_class, currency, tradable) VALUES
    ('ACME',    'Acme Corporation', 'EQUITY', 'USD', TRUE),
    ('AAPL',    'Apple Inc',        'EQUITY', 'USD', TRUE),
    ('INFY.NS', 'Infosys',          'EQUITY', 'INR', TRUE),
    ('DELIST',  'Delisted Holdings','EQUITY', 'USD', FALSE);

INSERT INTO accounts (account_id, holder_name, cash_balance, status, version, last_updated) VALUES
    ('ACC-000001', 'Priya Menon',   24500.75, 'ACTIVE',    0, TIMESTAMP '2026-09-28 09:14:22'),
    ('ACC-000002', 'Sean O''Neill',     0.50, 'ACTIVE',    3, TIMESTAMP '2026-09-28 09:14:22'),
    ('ACC-000003', 'Dana Whitfield', 1000.00, 'SUSPENDED', 0, TIMESTAMP '2026-09-28 09:14:22');

INSERT INTO positions (account_id, symbol, quantity, average_cost) VALUES
    (1, 'ACME', 100, 25.50),
    (1, 'AAPL',   0, 230.00);

-- =============================================================================
-- Enterprise Trading Platform: seed data
-- =============================================================================
--
-- Runs after 01-schema.sql, in the same first-boot init pass. This is the
-- canonical seed set: every service built against this platform assumes
-- these exact account numbers, symbols and identifiers. Do not renumber an
-- account or rename an instrument here without checking who depends on it.
--
-- Coverage, per docs/contracts/database-schema.sql's seed requirements:
--   - ACTIVE accounts with cash, for the happy path (1, 2, 3)
--   - one SUSPENDED and one CLOSED account, to exercise ACC-403 (4, 5)
--   - a non-tradable instrument, to exercise INS-404 (ENRN)
--   - orders spanning NEW, FILLED, REJECTED and CANCELLED
--   - positions on accounts 1 to 3 that reconcile against their FILLED orders
--
-- Re-running this file against a live database: it does not. It is a
-- first-boot init script. To reset, drop the postgres volume and let Docker
-- Compose recreate it; see infra/README.md.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- INSTRUMENTS
-- Eight tradable US names plus one non-tradable instrument for INS-404.
-- -----------------------------------------------------------------------------
INSERT INTO instruments (symbol, name, asset_class, currency, tradable) VALUES
    ('AAPL', 'Apple Inc.',                     'EQUITY', 'USD', TRUE),
    ('MSFT', 'Microsoft Corporation',          'EQUITY', 'USD', TRUE),
    ('GOOGL','Alphabet Inc. Class A',          'EQUITY', 'USD', TRUE),
    ('AMZN', 'Amazon.com Inc.',                'EQUITY', 'USD', TRUE),
    ('TSLA', 'Tesla Inc.',                     'EQUITY', 'USD', TRUE),
    ('NVDA', 'NVIDIA Corporation',             'EQUITY', 'USD', TRUE),
    ('JPM',  'JPMorgan Chase & Co.',           'EQUITY', 'USD', TRUE),
    ('SPY',  'SPDR S&P 500 ETF Trust',         'ETF',    'USD', TRUE),
    ('ENRN', 'Enron Corporation, delisted',    'EQUITY', 'USD', FALSE);

COMMENT ON TABLE instruments IS 'Tradable instruments. Reference data, rarely written. ENRN is seeded non-tradable to exercise INS-404.';


-- -----------------------------------------------------------------------------
-- ACCOUNTS
-- Numeric ids are assigned explicitly so that the seed set is reproducible
-- across every environment that runs this script. The identity sequence is
-- restarted afterwards so that accounts created through the application
-- continue from 6.
-- -----------------------------------------------------------------------------
INSERT INTO accounts (id, account_id, holder_name, cash_balance, status) OVERRIDING SYSTEM VALUE VALUES
    (1, 'ACC-1001', 'Priya Menon',    125000.00, 'ACTIVE'),
    (2, 'ACC-1002', 'Daniel Ortiz',   250000.00, 'ACTIVE'),
    (3, 'ACC-1003', 'Wei Zhang',       25000.00, 'ACTIVE'),
    (4, 'ACC-1004', 'Fatima Al-Sayed', 50000.00, 'SUSPENDED'),
    (5, 'ACC-1005', 'Conor Byrne',     90000.00, 'CLOSED');

ALTER TABLE accounts ALTER COLUMN id RESTART WITH 6;

-- Account 3 sits close to its lower cash bound deliberately: a modest order
-- against it is enough to exercise ORD-400 without needing an oversized one.
-- Account 4 is SUSPENDED and account 5 is CLOSED, to exercise ACC-403.


-- -----------------------------------------------------------------------------
-- ORDERS
-- A spread across every terminal and working status. Orders are seeded only
-- for the three ACTIVE accounts: a SUSPENDED or CLOSED account with order
-- history would suggest it traded after losing ACTIVE status, which the
-- business rules forbid.
--
-- FILLED orders carry executed_price and executed_on. REJECTED orders carry
-- reject_reason. NEW and CANCELLED orders carry neither. Every FILLED order
-- below is reflected in the POSITIONS block that follows: the two tables
-- must reconcile, because positions are derived state.
-- -----------------------------------------------------------------------------

-- Account 1, Priya Menon
INSERT INTO orders (id, account_id, symbol, side, quantity, price, status, idempotency_key, created_on, executed_price, executed_on, reject_reason) VALUES
    ('a1111111-0000-4000-8000-000000000001', 1, 'AAPL', 'BUY',  100, 233.00, 'FILLED',    'idem-a1-001', '2026-07-01 09:14:22', 232.71, '2026-07-01 09:14:24', NULL),
    ('a1111111-0000-4000-8000-000000000002', 1, 'AAPL', 'BUY',   50, 235.00, 'FILLED',    'idem-a1-002', '2026-07-03 10:02:11', 234.10, '2026-07-03 10:02:13', NULL),
    ('a1111111-0000-4000-8000-000000000003', 1, 'MSFT', 'BUY',   40, 410.00, 'FILLED',    'idem-a1-003', '2026-07-08 11:45:52', 409.50, '2026-07-08 11:45:54', NULL),
    ('a1111111-0000-4000-8000-000000000004', 1, 'SPY',  'BUY',   10, 550.00, 'NEW',       'idem-a1-004', '2026-08-04 08:30:00', NULL,   NULL,                  NULL),
    ('a1111111-0000-4000-8000-000000000005', 1, 'TSLA', 'BUY',   20, 260.00, 'REJECTED',  'idem-a1-005', '2026-07-15 14:20:37', NULL,   NULL,                  'PRICE_NOT_MET'),
    ('a1111111-0000-4000-8000-000000000006', 1, 'MSFT', 'SELL',  10, 415.00, 'CANCELLED', 'idem-a1-006', '2026-07-20 16:05:19', NULL,   NULL,                  NULL);

-- Account 2, Daniel Ortiz
INSERT INTO orders (id, account_id, symbol, side, quantity, price, status, idempotency_key, created_on, executed_price, executed_on, reject_reason) VALUES
    ('a2222222-0000-4000-8000-000000000001', 2, 'GOOGL', 'BUY',  30, 168.00, 'FILLED',    'idem-a2-001', '2026-07-02 09:00:05', 167.55, '2026-07-02 09:00:07', NULL),
    ('a2222222-0000-4000-8000-000000000002', 2, 'AMZN',  'BUY',  25, 186.00, 'FILLED',    'idem-a2-002', '2026-07-06 13:11:44', 185.90, '2026-07-06 13:11:46', NULL),
    ('a2222222-0000-4000-8000-000000000003', 2, 'GOOGL', 'SELL', 10, 170.00, 'FILLED',    'idem-a2-003', '2026-07-12 15:38:29', 169.80, '2026-07-12 15:38:31', NULL),
    ('a2222222-0000-4000-8000-000000000004', 2, 'NVDA',  'BUY',  15, 135.00, 'NEW',       'idem-a2-004', '2026-08-05 07:55:12', NULL,   NULL,                  NULL),
    ('a2222222-0000-4000-8000-000000000005', 2, 'JPM',   'BUY',  20, 238.00, 'REJECTED',  'idem-a2-005', '2026-07-22 10:47:03', NULL,   NULL,                  'PRICE_NOT_MET');

-- Account 3, Wei Zhang
INSERT INTO orders (id, account_id, symbol, side, quantity, price, status, idempotency_key, created_on, executed_price, executed_on, reject_reason) VALUES
    ('a3333333-0000-4000-8000-000000000001', 3, 'SPY', 'BUY',  40, 550.00, 'FILLED',    'idem-a3-001', '2026-07-04 09:20:00', 549.20, '2026-07-04 09:20:02', NULL),
    ('a3333333-0000-4000-8000-000000000002', 3, 'SPY', 'SELL', 20, 600.00, 'REJECTED',  'idem-a3-002', '2026-07-18 12:10:41', NULL,   NULL,                  'PRICE_NOT_MET'),
    ('a3333333-0000-4000-8000-000000000003', 3, 'JPM', 'BUY',   5, 239.00, 'NEW',       'idem-a3-003', '2026-08-05 08:02:47', NULL,   NULL,                  NULL),
    ('a3333333-0000-4000-8000-000000000004', 3, 'SPY', 'BUY',  10, 551.00, 'CANCELLED', 'idem-a3-004', '2026-07-25 09:41:18', NULL,   NULL,                  NULL);


-- -----------------------------------------------------------------------------
-- POSITIONS
-- Net effect of the FILLED orders above, accounts 1 to 3 only.
--
-- AAPL, account 1: 100 @ 232.71, then 50 @ 234.10.
--   (100 * 232.71 + 50 * 234.10) / 150 = 233.17
-- GOOGL, account 2: 30 @ 167.55, then a 10-unit sell leaves quantity at 20
--   and average cost unchanged at 167.55, per the sell rule.
-- -----------------------------------------------------------------------------
INSERT INTO positions (account_id, symbol, quantity, average_cost) VALUES
    (1, 'AAPL',  150, 233.17),
    (1, 'MSFT',   40, 409.50),
    (2, 'GOOGL',  20, 167.55),
    (2, 'AMZN',   25, 185.90),
    (3, 'SPY',    40, 549.20);

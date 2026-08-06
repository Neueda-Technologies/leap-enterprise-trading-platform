-- =============================================================================
-- Auth service schema: users and refresh tokens (PostgreSQL)
-- Sprint 8. Applied to the same database as contracts/database-schema.sql.
-- =============================================================================
--
-- WHY THIS FILE LIVES IN THE SERVICE
--
-- The operational tables (accounts, instruments, orders, positions) are owned by
-- the Sprint 3 schema and are created by the shared database init scripts. The
-- credential store is owned by this service and by nothing else, so its DDL
-- ships with the service that owns it. Two teams changing one init script is how
-- migrations start conflicting.
--
-- The auth tables live in their own schema, auth, for the same reason. The
-- application role used by the Trade REST API has no grant on auth.users, so a
-- SQL injection defect in the trading path cannot read a password hash.
--
-- HOW IT IS APPLIED
--
-- Two supported routes, and only one of them is on by default:
--
--   1. Service-run bootstrap (default). On boot the service executes this file
--      inside one transaction. Every statement is idempotent, so a restart is a
--      no-op. Controlled by AUTH_RUN_MIGRATIONS, default true. This is the
--      default because the service must come up on a database that a
--      participant created by hand, without a second manual step.
--   2. Infrastructure-run. Set AUTH_RUN_MIGRATIONS=false and have the platform
--      infrastructure apply this file, for example by mounting it into the
--      Postgres container's /docker-entrypoint-initdb.d directory alongside the
--      Sprint 3 schema, or by running:
--
--        psql -h localhost -U postgres -d trading -f migrations/users.sql
--
-- Use route 2 wherever the service connects as a least-privilege role with no
-- DDL rights, which is what a production deployment should do.
--
-- ORDERING AGAINST THE SPRINT 3 SCHEMA
--
-- users.account_id references accounts.id, the numeric surrogate key. The
-- foreign key is added only if the accounts table already exists, so that this
-- file applies cleanly whether or not the trading schema has been created yet.
-- Where the constraint is skipped, the service still validates the account at
-- registration time with a query. Re-running this file after the accounts table
-- appears adds the constraint.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS auth;

-- gen_random_uuid() is built in from PostgreSQL 13 onwards. The extension is
-- kept for older servers and is a no-op on 16 and 17. Creating an extension
-- needs superuser, which a least-privilege application role does not have, so
-- the failure is caught rather than allowed to abort the bootstrap.
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
EXCEPTION
    WHEN insufficient_privilege THEN
        RAISE NOTICE 'pgcrypto not created: relying on the built-in gen_random_uuid()';
END
$$;


-- -----------------------------------------------------------------------------
-- USERS
-- One row per person who can log in. The only table in the platform that holds a
-- password hash, and the only table this service writes to besides its own
-- refresh tokens.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auth.users (
    id             UUID          NOT NULL DEFAULT gen_random_uuid(),
    username       VARCHAR(64)   NOT NULL,
    password_hash  TEXT          NOT NULL,
    account_id     BIGINT        NOT NULL,
    roles          TEXT[]        NOT NULL DEFAULT ARRAY['CUSTOMER']::TEXT[],
    created_on     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_users PRIMARY KEY (id),
    CONSTRAINT uq_users_username UNIQUE (username),
    CONSTRAINT ck_users_username_pattern CHECK (username ~ '^[a-zA-Z0-9._-]{3,64}$'),
    CONSTRAINT ck_users_roles_non_empty CHECK (cardinality(roles) > 0),
    CONSTRAINT ck_users_roles_known CHECK (roles <@ ARRAY['CUSTOMER', 'ADMIN']::TEXT[])
);

COMMENT ON TABLE  auth.users IS 'Credential store. Owned by the auth service. No other service reads it.';
COMMENT ON COLUMN auth.users.id IS
    'Surrogate key, and the value carried in the JWT sub claim. A UUID rather than a sequence so that a token does not disclose how many users exist.';
COMMENT ON COLUMN auth.users.password_hash IS
    'argon2id encoded hash, salt and parameters included. Never a plain hash, never reversible, never logged.';
COMMENT ON COLUMN auth.users.account_id IS
    'References accounts.id, the numeric surrogate key, not accounts.account_id. This is the value carried in the JWT accountId claim.';
COMMENT ON COLUMN auth.users.roles IS
    'Authorisation roles. Always at least one. Set by the service, never by the request body on the public registration route.';

CREATE INDEX IF NOT EXISTS ix_users_account_id
    ON auth.users (account_id);


-- -----------------------------------------------------------------------------
-- REFRESH TOKENS
-- One row per issued refresh token. Rows are kept after use, not deleted,
-- because a token presented twice is the signal that a token was stolen and the
-- consumed row is the evidence.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auth.refresh_tokens (
    id           UUID         NOT NULL DEFAULT gen_random_uuid(),
    user_id      UUID         NOT NULL,
    token_hash   CHAR(64)     NOT NULL,
    issued_on    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    expires_on   TIMESTAMPTZ  NOT NULL,
    consumed_on  TIMESTAMPTZ,
    revoked_on   TIMESTAMPTZ,

    CONSTRAINT pk_refresh_tokens PRIMARY KEY (id),
    CONSTRAINT uq_refresh_tokens_hash UNIQUE (token_hash),
    CONSTRAINT fk_refresh_tokens_user
        FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);

COMMENT ON TABLE  auth.refresh_tokens IS 'Issued refresh tokens. Opaque to the client, hashed at rest, single use.';
COMMENT ON COLUMN auth.refresh_tokens.token_hash IS
    'SHA-256 of the token the client holds. Storing the token itself would mean a database read is a session takeover.';
COMMENT ON COLUMN auth.refresh_tokens.consumed_on IS
    'Set when the token is exchanged. A second presentation of a consumed token revokes every live token for the user.';
COMMENT ON COLUMN auth.refresh_tokens.revoked_on IS
    'Set by a logout, by an administrator, or by the theft response above. A revoked token never refreshes again.';

-- The refresh path looks a token up by hash; the theft response revokes by user.
CREATE INDEX IF NOT EXISTS ix_refresh_tokens_user_live
    ON auth.refresh_tokens (user_id)
    WHERE consumed_on IS NULL AND revoked_on IS NULL;


-- -----------------------------------------------------------------------------
-- CONDITIONAL FOREIGN KEY TO THE TRADING SCHEMA
-- Added only when the Sprint 3 accounts table exists and the constraint is not
-- already present. Keeps this file applicable to an empty database.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF to_regclass('public.accounts') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM pg_constraint WHERE conname = 'fk_users_account'
       )
    THEN
        ALTER TABLE auth.users
            ADD CONSTRAINT fk_users_account
            FOREIGN KEY (account_id) REFERENCES public.accounts (id);
    END IF;
END
$$;


-- -----------------------------------------------------------------------------
-- LEAST-PRIVILEGE NOTE
-- The auth service is the only role that needs these tables. Commented out
-- because role names and passwords come from the environment, never from a
-- committed file.
-- -----------------------------------------------------------------------------
-- CREATE ROLE auth_app LOGIN PASSWORD :'auth_password';
-- GRANT CONNECT ON DATABASE trading TO auth_app;
-- GRANT USAGE ON SCHEMA auth TO auth_app;
-- GRANT SELECT, INSERT, UPDATE ON auth.users, auth.refresh_tokens TO auth_app;
-- GRANT SELECT ON public.accounts TO auth_app;
-- No grant on auth.users for trading_app. A defect in the trading path must not
-- be able to read a password hash.

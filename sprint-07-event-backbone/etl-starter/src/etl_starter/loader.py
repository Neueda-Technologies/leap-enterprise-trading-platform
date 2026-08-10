"""Loads accounts, instruments and orders out of Postgres and into the star
schema in DuckDB.

Run it with `python -m etl_starter` or with the `etl-starter` console script.
See README.md in this folder for the environment variables it reads and for
the SQL it expects the operational database to answer.
"""

import datetime
import os
import sys

import duckdb
import psycopg

# The warehouse tables. Kept close to contracts/analytics-schema.sql, with the
# constraints trimmed to what DuckDB needs to accept the statements.
SCHEMA = """
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
    CONSTRAINT pk_dim_instrument PRIMARY KEY (instrument_key)
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
    CONSTRAINT pk_dim_date PRIMARY KEY (date_key)
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
    CONSTRAINT pk_fact_trades PRIMARY KEY (trade_key)
);
"""

DAY_NAMES = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
]

MONTH_NAMES = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
]


def exchange_for(symbol):
    """Venue, derived from the Fauxnance symbol scheme."""
    if symbol.startswith("FX:"):
        return "FX"
    if symbol.startswith("X:"):
        return "CRYPTO"
    if symbol.endswith(".NS"):
        return "NSE"
    if symbol.endswith(".BO"):
        return "BSE"
    return "US"


def rows(cursor, sql):
    """Run a read and hand back everything it returned."""
    cursor.execute(sql)
    return cursor.fetchall()


def run_load(since=None):
    """Read the operational database and load the warehouse.

    `since` is an optional ISO date. When it is given only orders created on or
    after that date are read.
    """
    warehouse = duckdb.connect(os.environ.get("WAREHOUSE_PATH", "warehouse.duckdb"))
    for statement in SCHEMA.split(";"):
        if statement.strip():
            warehouse.execute(statement)

    dsn = "host=%s port=%s dbname=%s user=%s password=%s" % (
        os.environ.get("PG_HOST", "localhost"),
        os.environ.get("PG_PORT", "5432"),
        os.environ.get("PG_DATABASE", "trading"),
        os.environ.get("PG_USER", "postgres"),
        os.environ.get("PG_PASSWORD", "postgres_dev_password"),
    )
    source = psycopg.connect(dsn)
    cursor = source.cursor()

    loaded_at = datetime.datetime.now()
    today = datetime.date.today()

    instrument_keys = {}
    next_instrument_key = warehouse.execute(
        "SELECT COALESCE(MAX(instrument_key), 0) FROM dim_instrument"
    ).fetchone()[0]
    for symbol, name, asset_class, currency, tradable in rows(
        cursor,
        "SELECT symbol, name, asset_class, currency, tradable FROM instruments ORDER BY symbol",
    ):
        next_instrument_key = next_instrument_key + 1
        warehouse.execute(
            "INSERT INTO dim_instrument VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            [
                next_instrument_key,
                symbol,
                name,
                asset_class,
                currency,
                exchange_for(symbol),
                tradable,
                loaded_at,
            ],
        )
        instrument_keys[symbol] = next_instrument_key

    account_keys = {}
    next_account_key = warehouse.execute(
        "SELECT COALESCE(MAX(account_key), 0) FROM dim_account"
    ).fetchone()[0]
    for source_id, account_id, holder_name, status in rows(
        cursor,
        "SELECT id, account_id, holder_name, status FROM accounts ORDER BY id",
    ):
        next_account_key = next_account_key + 1
        warehouse.execute(
            "INSERT INTO dim_account VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                next_account_key,
                account_id,
                holder_name,
                status,
                today,
                None,
                True,
                source_id,
                loaded_at,
            ],
        )
        account_keys[source_id] = next_account_key

    order_sql = (
        "SELECT id, account_id, symbol, side, quantity, price, status, "
        "executed_price, created_on FROM orders"
    )
    if since:
        order_sql = order_sql + " WHERE created_on >= '" + since + "'"
    order_sql = order_sql + " ORDER BY created_on"
    orders = rows(cursor, order_sql)

    known_dates = set()
    for row in warehouse.execute("SELECT date_key FROM dim_date").fetchall():
        known_dates.add(row[0])

    for order in orders:
        created_on = order[8]
        if created_on is None:
            continue
        day = created_on.date()
        date_key = day.year * 10000 + day.month * 100 + day.day
        if date_key in known_dates:
            continue
        warehouse.execute(
            "INSERT INTO dim_date VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                date_key,
                day,
                day.day,
                day.month,
                day.year,
                (day.month - 1) // 3 + 1,
                day.weekday() + 1,
                DAY_NAMES[day.weekday()],
                MONTH_NAMES[day.month - 1],
                day.weekday() < 5,
            ],
        )
        known_dates.add(date_key)

    next_trade_key = warehouse.execute(
        "SELECT COALESCE(MAX(trade_key), 0) FROM fact_trades"
    ).fetchone()[0]
    loaded = 0
    for order in orders:
        try:
            order_id = order[0]
            account_id = order[1]
            symbol = order[2]
            side = order[3]
            quantity = order[4]
            price = order[5]
            status = order[6]
            executed_price = order[7]
            created_on = order[8]

            if account_id not in account_keys:
                continue
            if symbol not in instrument_keys:
                continue
            if created_on is None:
                continue

            day = created_on.date()
            date_key = day.year * 10000 + day.month * 100 + day.day
            trade_value = quantity * price

            next_trade_key = next_trade_key + 1
            warehouse.execute(
                "INSERT INTO fact_trades VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    next_trade_key,
                    account_keys[account_id],
                    instrument_keys[symbol],
                    date_key,
                    side,
                    quantity,
                    price,
                    status,
                    executed_price,
                    trade_value,
                    str(order_id),
                    created_on,
                    loaded_at,
                ],
            )
            loaded = loaded + 1
        except Exception:
            continue

    warehouse.close()
    cursor.close()
    source.close()

    print("warehouse: " + os.environ.get("WAREHOUSE_PATH", "warehouse.duckdb"))
    print("instruments: %d" % len(instrument_keys))
    print("accounts: %d" % len(account_keys))
    print("trades loaded: %d" % loaded)
    return loaded


def main():
    since = None
    if len(sys.argv) > 2 and sys.argv[1] == "--since":
        since = sys.argv[2]
    elif len(sys.argv) > 1:
        print("usage: etl-starter [--since YYYY-MM-DD]")
        return 2
    run_load(since)
    return 0


if __name__ == "__main__":
    sys.exit(main())

# The batch loader

This loader reads accounts, instruments and orders out of the operational
Postgres database and writes the star schema in
`contracts/analytics-schema.sql` into a DuckDB file. It runs today, against a
seeded stack, and it produces a warehouse the Sprint 4 dashboard can read.

It is also the code you are asked to characterise and then refactor this
sprint. Read the sprint README before you change a line of it. The short
version: write the tests first, commit them, and only then touch this folder.

## Running it

The loader needs the operational database up and seeded, which means the
compose stack and your Sprint 3 schema.

Everything below runs from the repository root.

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -e 'sprint-07-event-backbone/etl-starter[dev]'

WAREHOUSE_PATH=warehouse.duckdb \
PG_HOST=localhost PG_PASSWORD=postgres_dev_password \
  .venv/bin/python -m etl_starter
```

It prints what it loaded:

```
warehouse: warehouse.duckdb
instruments: 8
accounts: 5
trades loaded: 34
```

Read the result back:

```bash
.venv/bin/python -c "import duckdb; print(duckdb.connect('warehouse.duckdb').execute('SELECT COUNT(*) FROM fact_trades').fetchone())"
```

One optional argument limits the read to orders created on or after a date:

```bash
WAREHOUSE_PATH=warehouse.duckdb PG_HOST=localhost PG_PASSWORD=postgres_dev_password \
  .venv/bin/python -m etl_starter --since 2026-09-01
```

## What it reads from

| Variable | Default | Purpose |
|---|---|---|
| `WAREHOUSE_PATH` | `warehouse.duckdb` | The DuckDB file the star schema is written to |
| `PG_HOST` | `localhost` | The operational database |
| `PG_PORT` | `5432` | |
| `PG_DATABASE` | `trading` | |
| `PG_USER` | `postgres` | |
| `PG_PASSWORD` | `postgres_dev_password` | The development password from `.env.example` |

Three statements run against the operational database, and they assume the
column names the Sprint 3 material converges on:

```sql
SELECT symbol, name, asset_class, currency, tradable FROM instruments;
SELECT id, account_id, holder_name, status FROM accounts;
SELECT id, account_id, symbol, side, quantity, price, status,
       executed_price, created_on FROM orders;
```

If your schema spells any of those differently, correct the statements. If your
`orders` table has no `executed_price` yet, add it with this sprint's other
schema changes: the Trade Executor writes the price a fill happened at, and the
analytical model needs it.

The loader connects as whatever `PG_USER` names. Point it at a role with
`SELECT` and nothing else. A pipeline that connects as the schema owner can
drop the table it is reading.

## Fixtures

`fixtures/source-rows.json` holds one snapshot of what those three statements
return against a seeded database, including the awkward rows an operational
database is perfectly happy to contain. Tests that use it run in milliseconds
and need no Postgres.

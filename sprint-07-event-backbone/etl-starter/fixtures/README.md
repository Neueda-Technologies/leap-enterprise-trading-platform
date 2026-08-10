# Fixtures

`source-rows.json` is a snapshot of what the loader's three read statements
return against a seeded operational database. It exists so that a test can put
rows through the loader without a Postgres container, a network, or a wait.

Three keys, one per statement, and the values are arrays of rows in the column
order the statement selects.

| Key | Column order |
|---|---|
| `instruments` | `symbol, name, asset_class, currency, tradable` |
| `accounts` | `id, account_id, holder_name, status` |
| `orders` | `id, account_id, symbol, side, quantity, price, status, executed_price, created_on` |

`created_on` is written as an ISO 8601 string here and arrives from the driver
as a `datetime`. Convert it when you load the fixture, or the loader will not
see what it sees in production.

The rows are not all tidy. An operational database enforces its own
constraints and no more, so a snapshot of one contains rows that satisfy every
constraint on `orders` and still make no sense in a warehouse. Those are the
interesting ones.

Add your own rows alongside these. Do not edit the ones that are here: a test
somebody else wrote is probably asserting against them.

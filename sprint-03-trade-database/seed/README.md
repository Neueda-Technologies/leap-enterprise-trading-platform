# Seed data

Fixture rows, as `.sql` files, applied after every migration has run. Number
them the same way as migrations if you use more than one file, for example
`001_instruments.sql` then `002_accounts.sql`, because insert order has to
respect your foreign keys.

Keep seed data out of `migrations/`. The two are reloaded on different
schedules: you will rebuild the schema without wanting fixtures, and reload
fixtures without wanting to rebuild the schema.

## What the data has to cover

Seed data is not decoration. It is the fixture set that Sprint 4 analyses,
that Sprint 6 tests against, and that every error path in
`contracts/trade-api.yaml` needs in order to be reachable. A seed file
containing one happy customer buying one share leaves most of the platform
untestable.

| Coverage | Why it is needed |
|---|---|
| Accounts in all three states, `ACTIVE`, `SUSPENDED` and `CLOSED` | The refusal paths for a frozen and a finished account |
| An account whose balance cannot afford a realistic order | The insufficient funds path |
| An account holding a position | Selling something, and the refusal to sell more than is held |
| Several instruments, at least one not an equity | Asset class handling, and the Sprint 4 breakdown by class |
| At least one instrument no longer tradable | The refusal to trade a delisted name |
| Orders in more than one lifecycle state, including a rejection | Order history and status filtering |
| Holdings consistent with the filled orders that produced them | Reconciling positions against order history, which you should be able to demonstrate |

Use symbols the market-data API actually serves. The base URL and the endpoint
list are in the root `README.md`. Inventing tickers costs you a pass over
every fixture in Sprint 7 when no quote resolves.

Spread creation timestamps across several weeks rather than stamping every row
with the same instant. Query 5 in the sprint brief, the incremental extract,
returns everything or nothing against a fixture set created in one second, and
Sprint 4 has nothing to plot.

## Reloading

```bash
sprint-03-trade-database/scripts/apply.sh
```

Applies migrations and then these files. Inserts that collide with rows
already present will fail, which is correct: seed data is loaded into a known
state, not merged into an unknown one. To reload cleanly:

```bash
sprint-03-trade-database/scripts/apply.sh --fresh
```

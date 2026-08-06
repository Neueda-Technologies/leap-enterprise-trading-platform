# Portfolio and P&L service

Reference implementation of the Sprint 10 Portfolio and P&L extension. Implements
`docs/contracts/portfolio-api.yaml` exactly: portfolio summary, priced positions,
profit and loss, and a health check. Spring Boot 3.3, Java 21, port 8081.

## Why this service exists

The Trade REST API returns positions unpriced: quantity and average cost, nothing
more. Pricing a position needs a live quote, and pulling a quote inside the order
write path would put a third-party HTTP call, with its own latency and its own
failure modes, into the transaction that records a trade. This service reads the
same positions, prices them against the Fauxnance API, computes profit and loss, and
is allowed to fail without stopping anyone from trading. The full reasoning is in the
contract; this file covers how the reference implementation meets it.

## What it reads and writes

| Data | Source | Access |
|---|---|---|
| Account, cash balance | `accounts` in Postgres | Read-only |
| Instrument currency | `instruments` in Postgres | Read-only |
| Quantity, average cost | `positions` in Postgres | Read-only |
| Last price | Fauxnance `GET /quotes?symbols=...`, batched, cached 10 seconds | HTTP |
| Realised profit and loss | `portfolio_realised_pnl`, owned by this service, built from `trade-events` | Read and write |

Nothing in the shared trading schema is ever written by this service. Its own write
path is the realised profit-and-loss ledger, created by
`src/main/resources/db/portfolio-schema.sql` and populated by
`kafka.TradeEventsConsumer`. See "Design decisions" below for why realised profit and
loss and cash balance are sourced this way rather than the other way the contract
permits.

## Design decisions

**Positions come straight from Postgres, not from a Kafka projection.** The contract
offers both options: read `positions`, or maintain a projection from `trade-events`.
This build reads `positions` directly. The Trade Executor already computes the
correct weighted average cost inside the transaction that fills an order; rebuilding
that logic here from `trade-events` would duplicate it and risk drifting from it.

**Cash balance comes from Postgres, not from a call to the Trade REST API.** The
contract lists `GET /api/v1/accounts/{id}/balance` as one source. This service
already holds a read connection to the same database, so it reads `accounts.cash_balance`
directly rather than adding a synchronous HTTP dependency on another service purely
to read one column. This is also why the health check reports exactly two
dependencies, Postgres and Fauxnance, and not three.

**Realised profit and loss is accumulated from `trade-events`, not recomputed from
`orders`.** The `ORDER_FILLED` payload on `trade-events` already carries
`executedPrice`, `quantity` and `averageCostAfter`. A sell leaves average cost
unchanged (see the comment on `positions.average_cost` in `database-schema.sql`), so
`averageCostAfter` on a SELL event equals the average cost at the moment of sale, and
`(executedPrice - averageCostAfter) * quantity` is the realised profit and loss on
that fill. No second read path into the trading database is needed to compute it.

**Average cost method: weighted average cost, not FIFO or LIFO.** This follows
`database-schema.sql` and `portfolio-api.yaml` directly, which define average cost as
a running weighted average recalculated on every buy. A team building this service
independently does not get to choose FIFO or LIFO: the Trade Executor already commits
to weighted average cost when it writes `positions.average_cost`, and the Portfolio
service must agree with it.

**Idempotency is a primary key, not an application check.** `portfolio_realised_pnl.event_id`
is the primary key. `PnlLedgerService.recordSaleIfNew` checks `existsById` first to
avoid unnecessary work, then relies on the unique constraint, not the check, to be
correct under a replay or a race. This is mechanism 1 from `kafka-topics.md`.

**Currency conversion is applied at the summary level only, not per position.**
`GET /positions` returns each holding in its own currency, matching the contract's
example response, which shows an INR position without conversion. `GET /{accountId}`
and `GET /pnl` need one number, so their totals are converted to `portfolio.base-currency`
(`USD` by default) using Fauxnance `FX:` pairs, for example `FX:INRUSD`. When no FX
quote is available for a held currency, that position's contribution is excluded from
the summary total and `partial` is set to `true`, rather than the request failing
outright or the total silently omitting the conversion. A team that trades only one
currency can set `PORTFOLIO_BASE_CURRENCY` to match it and never hits this path.

**`market-data` is consumed as a resilience fallback, not as the pricing source.**
The contract and the architecture diagram both show this service calling Fauxnance
directly for pricing. `MarketDataConsumer` additionally primes `QuoteCache` with the
last quote seen on the topic, marked stale. If a live Fauxnance call fails for a
symbol, `QuoteCache` serves this primed value instead of nothing, rather than pushing
the account into `MKT-503` because of one bad HTTP call. Live Fauxnance quotes always
take priority when they are available.

## Quote caching

`QuoteCache` batches up to 25 symbols per Fauxnance call (`fauxnance.quote-batch-size`)
and caches each symbol's quote for 10 seconds (`fauxnance.quote-cache-ttl-seconds`,
env `FAUXNANCE_QUOTE_CACHE_TTL_SECONDS`). The cache is keyed by symbol, not by
account, so two accounts holding the same instrument within the same 10-second window
share one Fauxnance call. This matters against the 2000-requests-per-day quota, which
is shared across every user of a key, not reset per account.

## Security

- Every `/api/**` route requires a bearer JWT, verified by `JwtAuthenticationFilter`
  with the same claims contract as the auth service (`sub`, `accountId`, `roles`,
  `iat`, `exp`, `iss`), HS256, secret from `JWT_SECRET`. `/health` is exempt.
- `PortfolioController` compares the token's `accountId` claim against the account
  requested in the path on every operation. A mismatch returns `403 ACC-403`, not
  `404`, and is logged, per the contract: a customer probing another account's
  portfolio is an access-control failure, not a lookup miss.
- The Fauxnance API key comes from `FAUXNANCE_API_KEY` and is attached server-side
  only. It is never logged and never reaches a response body.

## Error catalogue

| Code | HTTP | Meaning |
|---|---|---|
| `AUTH-401` | 401 | Missing, malformed, expired or wrongly signed token |
| `ACC-403` | 403 | Token's `accountId` claim does not match the account requested |
| `ACC-404` | 404 | No account exists with that key |
| `VAL-422` | 422 | Invalid input, for example `from` later than `to` |
| `MKT-503` | 503 | No price could be obtained for any held instrument |

An uncaught exception returns `500` with `errorCode: INTERNAL-500`. That code is not
part of the platform catalogue; it exists so the response body still matches the
`ErrorResponse` shape rather than falling back to a framework-generated page.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `DB_URL` | `jdbc:postgresql://localhost:5432/trading` | Postgres connection |
| `DB_USERNAME` / `DB_PASSWORD` | `trading_app` | A least-privilege role: `SELECT` on `accounts`, `instruments`, `positions`; full rights only on `portfolio_realised_pnl` |
| `KAFKA_BOOTSTRAP_SERVERS` | `localhost:9092` | Kafka broker |
| `JWT_SECRET` | dev-only placeholder | Must match the auth service |
| `FAUXNANCE_BASE_URL` | `https://y4t9nq2bqf.execute-api.eu-west-2.amazonaws.com/v1` | Fauxnance API |
| `FAUXNANCE_API_KEY` | none | Per-student key, required outside local stubs |
| `FAUXNANCE_QUOTE_CACHE_TTL_SECONDS` | `10` | Quote cache freshness window |
| `PORTFOLIO_BASE_CURRENCY` | `USD` | Currency `PortfolioSummary` and `PnlResponse` totals are expressed in |

## Running locally

```bash
export JWT_SECRET=dev-secret-change-me-dev-secret-change-me
export FAUXNANCE_API_KEY=your-key-here
mvn spring-boot:run
```

Or build the container:

```bash
docker build -t portfolio-pnl-service .
docker run -p 8081:8081 \
  -e DB_URL=jdbc:postgresql://host.docker.internal:5432/trading \
  -e JWT_SECRET=dev-secret-change-me-dev-secret-change-me \
  -e FAUXNANCE_API_KEY=your-key-here \
  -e KAFKA_BOOTSTRAP_SERVERS=host.docker.internal:9092 \
  portfolio-pnl-service
```

## Testing

`mvn test` runs two unit test suites, both free of Postgres, Kafka or Fauxnance:

- `pnl.PnlCalculatorTest`: weighted average cost on a buy, cost basis, market value,
  unrealised profit and loss and its percentage form, realised profit and loss on a
  full sale and on a partial sell, and total portfolio value. Figures are taken
  directly from the worked example in `portfolio-api.yaml` where one exists.
- `fauxnance.QuoteCacheTest`: a request inside the 10-second window does not call
  Fauxnance again, a request after the window does, two symbols cache independently,
  and a Fauxnance failure on refresh falls back to the last cached quote marked
  stale. Time is advanced through an injectable `Clock`, not a real sleep.

Not covered by this test suite: JPA repository behaviour against a real Postgres
instance, the Kafka consumers end to end, and the JWT filter's HTTP-layer behaviour.
A team extending this service towards production should add a Testcontainers-backed
integration test for `TradeEventsConsumer`, since that is the one component whose
correctness genuinely depends on Postgres transaction semantics (the duplicate-insert
path in `PnlLedgerService.recordSaleIfNew`).

## Known limitations

- Currency conversion assumes one `FX:` pair per currency and does not attempt
  triangulation through a third currency.
- The dead-letter path described in `kafka-topics.md` is not wired up: a message
  that fails to parse is logged and acknowledged, not routed to `trade-events.DLT`.
  `TradeEventsConsumer` and `MarketDataConsumer` both call this out at the point it
  matters.
- `GET /health` calls Fauxnance `GET /usage` on every request rather than caching it,
  despite the schema note that it should be polled rarely. Acceptable for a
  reference build; a production deployment should cache this alongside the quote
  cache instead of spending quota on every health probe.

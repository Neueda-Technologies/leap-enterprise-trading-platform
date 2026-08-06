# Extensions

Sprint 10 of the Enterprise Trading Platform. By this point a team has the trading
domain engine, the Trade REST API, Kafka, the Trade Executor, the market-data poller
and the auth service in place. Extensions are what a team builds on top of that
platform to demonstrate depth: a service that consumes the events the core platform
already produces, or reads the data it already holds, and turns that into a feature a
customer would recognise.

An extension is a separate deployable service, not a module bolted onto the Trade
REST API. It has its own port, its own repository path under `extensions/`, and its
own security boundary: it verifies a JWT itself rather than trusting that a request
reaching it has already been checked.

## The six extensions

| Extension | Consumes | Owns |
|---|---|---|
| Portfolio and P&L | `trade-events`, `market-data`, Fauxnance quotes, the shared Postgres schema, read-only | Realised profit-and-loss ledger |
| Watchlists and price alerts | `market-data` | Watchlists, alert thresholds |
| Customer notifications | `trade-events` | Notification history and delivery state |
| Customer preferences and personalisation | nothing from Kafka | Channel and contact preferences |
| Trade advice and signals | `trade-events`, `market-data`, Fauxnance candles | Generated signals |
| Automated strategy execution | `trade-events`, `market-data` | Strategy configuration and its own order placement |

Design briefs for the five not built out in full are under `extensions/briefs/`, one
file per extension. `extensions/portfolio-pnl/` is the one reference implementation
in this repository, built in full against `docs/contracts/portfolio-api.yaml`.

## Policy by cohort

**US and Ireland (12 weeks).** One extension is mandatory. The team chooses which.
Assessment is on depth, integration quality and the security review for that one
service, so a narrow, well-built extension outscores a wide, thin one.

**India (9 weeks).** All six are recommended. Four are mandatory:

- Portfolio and P&L
- Watchlists and price alerts
- Customer preferences and personalisation
- Customer notifications

These four form one coherent customer-facing feature set: a customer sets a
preference, receives a notification through the channel they chose, and watches a
price move trigger an alert delivered the same way. Portfolio and P&L stands apart
from that set and has no dependency on the other three.

## Dependency warning

Two of the four India-mandatory extensions depend on a third:

- **Customer notifications depends on customer preferences.** A notification cannot
  be routed without a channel to route it to. Build customer preferences first.
- **Watchlists alerting depends on customer notifications.** A triggered price
  threshold is not an alert until it has been delivered somewhere. Build customer
  notifications before wiring up watchlist alerts, or build both in step and stub the
  half not yet ready.

The build order that respects both dependencies is: customer preferences, then
customer notifications, then watchlists and price alerts, with Portfolio and P&L
built in parallel at any point, since nothing else depends on it and it depends on
nothing else in the extension set.

A watchlist that writes a triggered alert only to a log has not met the acceptance
criterion for that extension. The alert must reach the notifications service, and the
notifications service must respect the customer's stored channel preference rather
than defaulting to one channel regardless of what was configured.

## Shared expectations

Every extension, mandatory or chosen, is held to the same bar as the core platform:

- Verify the JWT itself. Do not trust an API gateway or another service to have
  checked it first.
- Use the standard error envelope, `{errorCode, message}`, extending the platform
  catalogue with a service-specific code only where the platform catalogue has no
  code that fits, as `portfolio-api.yaml` does with `MKT-503`.
- State explicitly, in the service's own README, which Kafka consumer group it uses,
  and confirm that group identifier is not shared with any other service.
- Never call Fauxnance from the browser. A key reaching client-side JavaScript is a
  credential leak regardless of which extension did it.
- Ship a multi-stage Dockerfile and a README covering configuration, local run
  instructions and what the test suite does and does not cover.

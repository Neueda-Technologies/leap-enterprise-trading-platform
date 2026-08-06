# Automated strategy execution

## Purpose

Trade advice and signals tells a customer what a strategy would do; this extension
is the one allowed to act on it without a human confirming each trade. It is the
extension with the highest blast radius in the whole catalogue: a bug here places
real orders against real accounts. Treat every control below as load-bearing, not
optional hardening added after a demo works.

## Suggested architecture

Consume `trade-events` and `market-data`, group `strategy-service`, to evaluate
whether a configured strategy's entry or exit condition is met.

This extension does not produce to `orders` directly. Publishing straight onto the
topic skips the Trade REST API's business-rule validation and idempotency-key check,
the two things standing between a strategy bug and an unrecoverable bad trade. Place
orders the way the Angular UI does: call `POST /api/v1/orders`, authenticated, with a
strategy-generated `idempotencyKey`.

A strategy needs an identity to trade under. Decide whether it trades under the
owning customer's account and token or under a service identity scoped to that
account, and document the choice. Do not reuse a customer's access token outside the
request that customer initiated.

## Suggested endpoints

| Method and path | Purpose |
|---|---|
| `POST /api/v1/strategies` | Create a strategy configuration for an account: instrument, entry and exit rule, position sizing, an explicit maximum spend or maximum position size |
| `PUT /api/v1/strategies/{id}/enable` | Turn a strategy on. Must default to disabled on creation. |
| `PUT /api/v1/strategies/{id}/disable` | Turn a strategy off, immediately, mid-evaluation-cycle if necessary |
| `GET /api/v1/strategies/{id}/executions` | Every order this strategy has placed, and why |

## Data it owns

Strategy configurations, their enabled state, and an execution log distinct from
`orders`: this log records the strategy's own reasoning (which condition fired)
alongside the `orderId` the Trade REST API returned.

## Security considerations

- **OWASP A01, broken access control.** A strategy belongs to one account. Creating,
  enabling or reading one for a mismatched account is rejected the same way every
  other extension rejects it.
- **OWASP A04, insecure design**, the dominant risk here. A strategy with no maximum
  spend, no maximum position size, and no circuit breaker on repeated failures can
  place unbounded orders against a real balance. Enforce a hard cap in code, not
  only as a documented convention.
- **OWASP A08, software and data integrity failures.** If a strategy's rule is a
  configurable expression rather than a fixed set of built-in rule types, that is an
  injection surface: a customer-supplied expression evaluated server-side can do
  more than pick a trade. Prefer a small, fixed vocabulary of rule types.
- A disabled strategy must stop trading immediately, not after its next scheduled
  evaluation. Check the enabled flag at the point of decision, not only at start-up.

## Acceptance criteria a team must demo

- A strategy with a defined rule and a hard maximum spend, enabled, places a real
  order through the Trade REST API when its condition is met, appearing on the
  account's normal blotter, indistinguishable from a manually placed order.
- Disabling a strategy stops it from placing further orders, demonstrated live.
- A strategy cannot exceed its configured maximum spend, demonstrated by attempting
  to trigger it past the cap.

## Stretch goals

- Paper-trading mode: evaluate and log what the strategy would have done without
  calling the Trade REST API, for a customer testing a configuration.
- Multiple concurrent strategies per account with a shared account-level spend cap,
  not only a per-strategy one.
- A kill switch reachable outside the normal API, for an operator to halt every
  strategy platform-wide.

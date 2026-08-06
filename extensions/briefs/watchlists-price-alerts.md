# Watchlists and price alerts

## Purpose

A customer holds positions but also wants to track instruments they have not bought
yet, and wants to be told when a price crosses a level they care about, without
watching a screen for it. Nothing in the core platform does either: the Trade REST
API knows what a customer holds, not what they are curious about, and no service
turns a price tick into a message a customer sees. This extension owns both.

## Suggested architecture

Consume `market-data`, group `watchlist-service`. Every quote published by the
market-data poller passes through this consumer; the service checks it against the
active alert thresholds for that symbol and decides whether one has been crossed.

Do not consume `trade-events` or `orders`. A watchlist entry is not a position.

This extension has an unavoidable dependency: an alert is not delivered by writing it
to a log. It must reach customer notifications over HTTP, and customer notifications
must in turn respect the channel configured in customer preferences. Do not build
watchlists in isolation and defer the delivery integration; a triggered threshold
with nowhere to go is not a working feature.

Consider what "crossed" means before writing the check. A threshold set above the
current price triggers once the price rises through it; one set below triggers once
the price falls through it. Re-arm behaviour is a design decision this brief leaves
open: decide whether a triggered alert deactivates itself, requires the customer to
reset it, or re-triggers on every quote past the threshold, and state which one the
service implements.

## Suggested endpoints

| Method and path | Purpose |
|---|---|
| `POST /api/v1/watchlists` | Create a watchlist for the authenticated customer |
| `GET /api/v1/watchlists/{id}` | List entries and their current price |
| `POST /api/v1/watchlists/{id}/instruments` | Add an instrument to a watchlist |
| `DELETE /api/v1/watchlists/{id}/instruments/{symbol}` | Remove one |
| `POST /api/v1/alerts` | Create a price alert on a symbol, with a threshold and a direction |
| `GET /api/v1/alerts` | List the authenticated customer's alerts and their state |
| `DELETE /api/v1/alerts/{id}` | Cancel an alert |

## Data it owns

Watchlists, their member instruments, alert thresholds, and alert trigger history.
`instruments` and `positions` are read by symbol reference only, never duplicated.

## Security considerations

- **OWASP A01, broken access control.** A watchlist and its alerts belong to one
  customer. Every read and write must filter by the authenticated `accountId`, the
  same pattern the portfolio service uses to compare the JWT claim against the
  resource requested, not by a client-supplied identifier.
- **OWASP A04, insecure design.** An unrate-limited alert-creation endpoint lets one
  account create unbounded alerts and turn the market-data consumer into a
  denial-of-service vector against itself. Cap alerts per account.
- Verify the JWT independently, on every request, the same as every other service.

## Acceptance criteria a team must demo

- A customer creates a watchlist, adds an instrument, and sees its live price.
- A customer sets a price alert; a quote crossing the threshold produces a
  notification that actually reaches customer notifications, and that notification
  respects a channel preference set in customer preferences, end to end, not stubbed
  at any point in the chain.
- An alert on an instrument the customer does not hold still works: watchlists are
  independent of positions.

## Stretch goals

- Percentage-move alerts, in addition to absolute price levels.
- A WebSocket or server-sent-events feed pushing live watchlist prices to the UI,
  rather than the UI polling.
- Alert history with delivery status, so a customer can see an alert fired even if
  the notification failed.

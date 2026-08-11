# Watchlists and price alerts

A customer holds five instruments and is curious about twenty. The platform knows
about the five, because the Trade REST API records what they bought, and knows
nothing about the other fifteen. It also has no way to tell a customer that a
price they cared about has been crossed, so the only way to find out is to sit
and watch a screen. This extension owns both halves: the list of instruments a
customer is tracking, and the thresholds they want to be told about.

## Who uses it

The customer, in the Angular application: a watchlist with live prices beside
each entry, and alerts they can create, see the state of, and cancel. A watchlist
entry is not a position, and a customer must be able to watch something they have
never traded.

## What it integrates with

| Surface | How this service uses it |
|---|---|
| `market-data` | Consume, group `watchlist-service`. Every quote the poller publishes passes through this consumer, which checks it against the active thresholds for that symbol. |
| Customer notifications | Over HTTP. A triggered threshold is delivered through the notifications service, which resolves the customer's channel. |
| Trade REST API | Read-only, to resolve instrument reference data by symbol. Instruments and positions are referenced, never copied. |
| Angular application | Watchlist management, live prices, alert creation and alert state. |

Do not consume `orders` or `trade-events`. Neither says anything about what a
customer is curious about.

## The API is yours

There is no contract for this extension. Design the API, write it as OpenAPI
before you write the controller, and bring it to your instructor on day one for
review. The platform conventions still bind: the `{errorCode, message}` envelope,
the platform error catalogue extended only where nothing in it fits, and a bearer
token verified by this service itself.

## What makes it worth building

The consumer is the part worth thinking about. Every quote for every symbol
arrives here, and the service has to decide, per message, whether any customer
cares. That is a lookup on the hot path, and how it is indexed is a real decision
with a real answer.

Then there is the meaning of "crossed", which is less obvious than it looks. A
threshold above the current price triggers when the price rises through it; one
below triggers when it falls through it. What happens next is open: an alert can
deactivate itself, wait for the customer to reset it, or fire on every quote past
the level. The third choice sends a customer forty messages in a minute. Decide
which behaviour the service implements, and record why.

Delivery is where this extension stops being a private feature and becomes part
of the platform. An alert written to a log is not an alert.

## Scope for one week

Watchlists that a customer can create and add instruments to, with a live price
beside each entry. Price alerts with a threshold and a direction, evaluated
against the `market-data` stream, delivered through the notifications service to
the channel the customer configured. Alert state visible to the customer.

If your team is building this alone, the delivery target is a small service you
also stand up, or a delivery interface with one implementation and a clear seam
where Notifications would sit. Say which, on day one, before it becomes a
discovery on the Thursday.

Out of scope unless the rest is finished: percentage-move alerts, a push channel
to the browser, and alert history with per-delivery status.

## What to get right

- **Access control.** A watchlist and its alerts belong to one customer. Every
  read and write filters on the account in the verified token, never on an
  identifier the client supplied.
- **A cap per account.** An unbounded alert-creation route lets one account fill
  the table and turn your own `market-data` consumer into the thing that takes
  the service down.
- **Alerts are delivered.** The acceptance criterion is a notification that
  reaches a customer through the channel they chose, demonstrated end to end.
- **Verify the token yourself.** Every request, in this service, regardless of
  what checked it upstream.

# Customer notifications

An order is filled at nine in the morning and the customer finds out at four in
the afternoon, because that is when they next opened the blotter. A rejection is
worse: nothing on the platform tells anyone that the order they placed will never
happen. `trade-events` already carries every outcome that matters. This extension
is what turns one of those events into a message a customer actually receives, on
the channel they chose.

It is also the delivery route other features use. An alert, a signal or a
statement notice all end up here, so its reliability matters to more than its own
feature list.

## Who uses it

The customer, on whichever channel they configured: email, SMS or a push message.
The Angular application shows the same history as an inbox, so a customer who
missed a message can find it.

## What it integrates with

| Surface | How this service uses it |
|---|---|
| `trade-events` | Consume, group `notification-service`. `ORDER_FILLED`, `ORDER_REJECTED` and `ORDER_CANCELLED` are all newsworthy. |
| Customer preferences | Over HTTP, to resolve the channel before sending. |
| Angular application | Notification history, and marking a message read if you build an inbox. |
| An outbound channel | Email, SMS or push. A logging stub is acceptable for a channel you cannot provision, provided the routing decision is real. |

## The API is yours

There is no contract for this extension. Design the API, write it as OpenAPI
before you write the controller, and bring it to your instructor on day one for
review. The platform conventions still bind: the `{errorCode, message}` envelope,
the platform error catalogue extended only where nothing in it fits, and a bearer
token verified by this service itself.

## What makes it worth building

Consumption and delivery are two different failures, and separating them is the
design problem in this service. The Kafka offset says what has been read. The
delivery state says what has reached a customer. Commit the offset once the
notification is durably recorded for delivery, not once an external provider has
confirmed it, because an email provider having a bad afternoon should not stall a
partition and back up every other account on it. Track queued, sent and failed
separately from the offset.

Kafka delivers at least once, so a duplicated event must not produce a duplicated
message. The discipline is the one the Trade Executor already uses: key on
`eventId` and make the second attempt a no-op.

The last piece is the dependency. A notification cannot be routed without knowing
where to route it, so the channel comes from the preferences service rather than
from a constant in this one.

## Scope for one week

Consumption of the three order outcomes, resolution of the channel through
preferences, delivery on at least one real channel, notification history exposed
to the customer, and idempotency proven by replaying an event and showing that
nothing is sent twice.

If your team is building this alone, either stand up a small preferences service
alongside it or put the resolution behind an interface with one implementation
and a clear seam. Hardcoding a channel and calling the dependency satisfied is
the one shortcut this extension does not have.

Out of scope unless the rest is finished: digest batching, retry with backoff
that distinguishes a transient failure from a permanent one, and read receipts.

## What to get right

- **Access control.** Notification history is read by its owning account only,
  checked against the verified token.
- **Nothing sensitive in a message.** A payload that carries a credential, a full
  card number or anything `contracts/kafka-topics.md` prohibits from a message is
  a disclosure that outlives the incident. The outbound message is held to the
  same rule as the event.
- **No caller-supplied destinations.** A webhook target or channel URL that a
  customer can set, and that the service then fetches or posts to, is a
  server-side request forgery. Fix the destination per channel type or validate
  it hard.
- **A rejection is news.** A customer who only hears about successes has no idea
  their order failed.

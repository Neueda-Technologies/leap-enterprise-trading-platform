# Customer notifications

## Purpose

An order is filled, rejected or cancelled, and nobody tells the customer unless they
happen to be looking at the blotter at that moment. `trade-events` already carries
every outcome that matters; this extension is what turns one of those events into a
message a customer actually sees, on the channel they chose. It is also the delivery
target every other extension's alerts route through, so its reliability affects more
than its own feature list.

## Suggested architecture

Consume `trade-events`, group `notification-service`. Handle `ORDER_FILLED`,
`ORDER_REJECTED` and `ORDER_CANCELLED`; a rejection is exactly as newsworthy as a
fill; a customer who only hears about successes has no idea their order failed.

Before sending anything, call customer preferences (`GET /api/v1/preferences/{accountId}/notifications`)
to resolve the channel. This is the hard dependency the platform decisions record
explicitly: a notification cannot be routed without it. Build customer preferences
first, or stub its response behind the same interface while it is being built, but do
not hardcode a channel and call the dependency satisfied.

Offset commit and delivery are two different failures. Commit the Kafka offset after
the notification is durably queued for delivery, not after it is confirmed delivered
by an external channel; an email provider's outage should not stall this consumer's
partition. Track delivery state (queued, sent, failed) separately from consumption
state.

## Suggested endpoints or channels

| Method and path | Purpose |
|---|---|
| `GET /api/v1/notifications/{accountId}` | Notification history for the authenticated customer |
| `POST /api/v1/notifications/{accountId}/read` | Mark notifications as read, if the UI shows an inbox |
| Outbound: email, SMS, or push, per the resolved preference | Actual delivery. A logging stub is acceptable for a channel a team cannot provision (SMS credentials, for instance), provided the routing decision is real. |

## Data it owns

Notification history: what was sent, to which account, on which channel, and its
delivery state. Does not own preferences; it reads them.

## Security considerations

- **OWASP A01, broken access control.** Notification history is read by its owning
  account only, checked against the JWT claim.
- **OWASP A09, security logging failures, inverted.** A notification payload must
  never carry a credential, a full card number, or anything `kafka-topics.md`
  already prohibits from a message payload. Treat the outbound message the same way.
- **OWASP A10, server-side request forgery**, if a channel URL or webhook target is
  ever configurable per customer rather than fixed per channel type. Do not let a
  customer-supplied destination be fetched or posted to without validation.
- A duplicate `trade-events` delivery must not send the same notification twice.
  Apply the same idempotency discipline as the Trade Executor: key on `eventId`.

## Acceptance criteria a team must demo

- Filling an order produces a notification on the channel the customer configured in
  customer preferences, verified by changing the preference and showing the channel
  changes too.
- A rejected order also produces a notification, distinct in content from a fill.
- Replaying a consumed event does not send a second notification.

## Stretch goals

- Digest mode: batch several events into one message rather than one per event, for
  a customer who has opted out of real-time delivery.
- Delivery retry with backoff for a transient channel failure, distinguished from a
  permanent one (an invalid email address does not get retried).
- A read receipt or delivery confirmation surfaced back to the customer.

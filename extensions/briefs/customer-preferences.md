# Customer preferences and personalisation

## Purpose

Every other customer-facing extension needs to know something about the customer
beyond their trades: which channel to notify them on, which currency to show totals
in, which instruments to feature on their dashboard. Without a single place that
owns this, each extension invents its own copy, and the copies disagree. This
extension is that single place. It is deliberately the simplest of the six, both
because it has no Kafka dependency and because everything else in the India-mandatory
set depends on it existing first.

## Suggested architecture

This extension consumes nothing from Kafka. It is a plain CRUD service over its own
store, read by other services synchronously over HTTP.

Customer notifications calls it to resolve a channel before sending. Watchlists and
price alerts may call it to resolve display preferences. Do not have this service
call anyone else: it is a leaf dependency, and the whole point of building it first
is that nothing it does can be blocked on another extension being ready.

Because other services call this one synchronously and on a path that gates whether
a notification gets sent at all, its availability matters more than its feature
surface. Favour a small, reliable API over a large, fragile one.

## Suggested endpoints

| Method and path | Purpose |
|---|---|
| `GET /api/v1/preferences/{accountId}` | The full preference set for one account |
| `PUT /api/v1/preferences/{accountId}/notifications` | Channel choice: email, SMS, push, or a combination |
| `PUT /api/v1/preferences/{accountId}/display` | Base currency, theme, dashboard layout |
| `GET /api/v1/preferences/{accountId}/notifications` | The resolved channel, for other services to call |

## Data it owns

One preference record per account: notification channel and contact detail per
channel, display currency, and any other personalisation setting the team adds. Do
not store a copy of anything `accounts` already owns, such as the holder's name; look
it up if a display needs it.

## Security considerations

- **OWASP A01, broken access control.** A customer reads and writes only their own
  preferences. Compare the JWT's `accountId` claim against the path parameter on
  every route, the same check every other extension makes.
- **OWASP A02, cryptographic failures.** A contact detail, an email address or a
  phone number, is personal data. If it is stored anywhere other services already
  hold it (the auth service, for instance), consider whether this service should
  store its own copy at all, or resolve it by account reference instead. Storing it
  twice doubles the places a leak can happen.
- **OWASP A05, security misconfiguration.** This service is called by other internal
  services, not by the browser directly, in most designs. Do not make its internal
  read endpoint (`GET .../notifications`) publicly reachable with the same
  authentication as the customer-facing routes; consider a separate, internal-only
  path or a service-to-service credential.

## Acceptance criteria a team must demo

- A customer sets a notification channel and a display currency, and both persist
  across a restart of the service.
- Customer notifications, called live, resolves the channel this service returns,
  not a hardcoded default.
- A request for another account's preferences is rejected, not silently returned
  empty.

## Stretch goals

- A preference history, so a customer can see when a channel was changed and revert
  it.
- Multiple contact points per channel (a work email and a personal email), with one
  marked primary.
- A webhook or event published when preferences change, so notifications does not
  need to call this service synchronously on every send.

# Customer preferences and personalisation

Every customer-facing feature on this platform needs to know something about the customer
beyond their trades. Which channel to reach them on. Which account to open on by default when
they sign in. Which currency to show a total in. Nothing owns any of that today, so each
feature that needs it invents its own copy, and within a fortnight the copies disagree and
nobody can say which one the customer actually set. This service is the single place that owns
it.

## Where it sits in the order

First of the four, and the reason it is first is that the next one cannot work without it. A
notification has no channel until something holds one, so notifications resolves the channel
through this service rather than holding a constant of its own. Watchlists reaches the same
preference one step further along the chain, through notifications.

| Direction | Service | What crosses the boundary |
|---|---|---|
| Provides | Customer notifications | The customer's alert channel, resolved before a message is sent |
| Depends on | Nothing in this sprint | This service can be built on Monday morning with nothing else running |

Because it is first and everything waits on it, its API is the first thing to agree and the
first thing to make real. A route that answers with a plausible shape, before its persistence
is finished, unblocks the rest of the team on Monday afternoon.

## Who uses it

The customer, through a settings screen in the Angular application, and again at sign-in
without knowing it, because the default account they set is the account the application opens
on. Other services, which call it to resolve a preference before they act.

## What it integrates with

| Surface | How this service uses it |
|---|---|
| Angular application | The settings screen, and the sign-in path that applies the stored default account |
| Customer notifications | Calls this service to resolve a channel before sending |
| Trade REST API | Read-only, to resolve an account when a screen needs the holder's details. Do not copy anything `accounts` already owns |
| Kafka | Nothing required. This service need consume no topic and produce none |

## The API is yours

There is no contract for this service. Design the API, write it as OpenAPI before you write the
controller, and bring it to your instructor on day one for review. The platform conventions
still bind: the `{errorCode, message}` envelope, the platform error catalogue extended only
where nothing in it fits, and a bearer token verified by this service itself.

Agree one thing with the notifications pair before either of you builds it: the exact route
notifications calls to resolve a channel, and what it answers when no preference has been set.
That is the seam, and it is cheaper to agree on Monday than to discover on Wednesday.

## What makes it worth building

Availability, not feature surface. Another service calls this one synchronously, on a path that
decides whether a customer gets told about their own trade. That inverts the usual priority: a
small API that is always there is worth more than a large one that is occasionally not.
Timeouts, a sensible default when this service is unreachable, and a decision about whether the
caller fails open or fails closed are the interesting parts, and every one of them is a decision
log entry.

The second question is what this service should hold at all. An email address and a telephone
number are personal data, and they may already exist somewhere else on the platform. Storing a
second copy doubles the number of places a leak can happen and creates a reconciliation problem
the day one of them changes. Deciding to store a reference rather than a copy is a defensible
answer, and so is the opposite, but the decision has to be taken rather than fallen into.

## Scope for one week

A preference record per customer covering, at a minimum, a default account and an alert channel
with its contact detail. Reads and writes from the Angular settings screen. A resolution route
the notification path can call. Persistence that survives a restart of the service, which the
acceptance criterion depends on: a preference that lives in memory is applied at the next login
only if nothing restarted in between.

The default account applied at the customer's next sign-in, in the Angular application, is part
of this deliverable rather than a nicety. It is what turns a stored row into a preference.

Out of scope unless the rest is finished: preference history and revert, multiple contact
points per channel, and publishing a change event so that callers do not have to ask.

## What to get right

- **Access control.** A customer reads and writes their own preferences only. The account comes
  from the verified token and is compared against the account in the path on every route.
- **The internal route is not the customer route.** The resolution route notifications calls
  should not be reachable by a customer with a customer's token under the same rules. Separate
  the path or use a service credential, and say which you chose.
- **Personal data.** Decide what is stored here, encrypt or reference what is sensitive, and
  keep contact details out of logs and out of Kafka payloads.
- **A default is a decision.** What the platform does when no preference has been set, and what
  a caller does when this service does not answer, are both behaviours somebody has to choose
  deliberately.

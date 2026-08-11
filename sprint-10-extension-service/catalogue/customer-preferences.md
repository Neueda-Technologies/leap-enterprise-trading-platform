# Customer preferences and personalisation

Every customer-facing feature on this platform needs to know something about the
customer beyond their trades. Which channel to reach them on. Which currency to
show a total in. Which instruments to put on the front of their dashboard.
Nothing owns any of that today, so each feature that needs it invents its own
copy, and within a fortnight the copies disagree and nobody can say which one the
customer actually set. This extension is the single place that owns it.

## Who uses it

The customer, through a settings screen in the Angular application. And other
services, which call it to resolve a preference before they act: notifications
asks it which channel to send on, a portfolio or watchlist screen asks it which
currency to render totals in.

## What it integrates with

| Surface | How this service uses it |
|---|---|
| Kafka | Nothing. This service consumes no topic and produces none. |
| Angular application | The settings screen: reading the preference set and writing changes. |
| Customer notifications | Calls this service to resolve a channel before sending. |
| Trade REST API | Read-only, to resolve an account when a screen needs the holder's details. Do not copy anything `accounts` already owns. |

## The API is yours

There is no contract for this extension. Design the API, write it as OpenAPI
before you write the controller, and bring it to your instructor on day one for
review. The platform conventions still bind: the `{errorCode, message}` envelope,
the platform error catalogue extended only where nothing in it fits, and a bearer
token verified by this service itself.

Note the integration requirement for the sprint when you scope this one: the
service has to integrate with Kafka or the Trade REST API. A preferences service
that talks to neither meets its own brief and not the sprint's, so agree the
integration surface with your instructor on day one. Publishing a
preference-changed event, or resolving account details through the Trade REST
API, are two answers.

## What makes it worth building

Availability, not feature surface. Another service calls this one synchronously,
on a path that decides whether a customer gets told about their own trade. That
inverts the usual priority: a small API that is always there is worth more than a
large one that is occasionally not. Timeouts, a sensible default when this
service is unreachable, and a decision about whether the caller fails open or
fails closed are the interesting parts, and every one of them is a decision log
entry.

The second question is what this service should hold at all. An email address and
a telephone number are personal data, and they may already exist somewhere else
on the platform. Storing a second copy doubles the number of places a leak can
happen and creates a reconciliation problem the day one of them changes. Deciding
to store a reference rather than a copy is a defensible answer, and so is the
opposite, but the decision has to be taken rather than fallen into.

## Scope for one week

A preference record per account covering at least a notification channel with its
contact detail and a display setting such as base currency. Reads and writes from
the Angular settings screen. A resolution route the notification path can call.
Persistence that survives a restart. The integration surface agreed on day one.

Out of scope unless the rest is finished: preference history and revert, multiple
contact points per channel, and publishing a change event so that callers do not
have to ask.

## What to get right

- **Access control.** A customer reads and writes their own preferences only. The
  account comes from the verified token and is compared against the account in
  the path on every route.
- **Personal data.** Decide what is stored here, encrypt or reference what is
  sensitive, and keep contact details out of logs and out of Kafka payloads.
- **The internal route is not the customer route.** A resolution route that other
  services call should not be reachable by a customer with a customer's token
  under the same rules. Separate the path or use a service credential, and say
  which you chose.
- **A default is a decision.** What the platform does when no preference has been
  set, and what a caller does when this service does not answer, are both
  behaviours somebody has to choose deliberately.

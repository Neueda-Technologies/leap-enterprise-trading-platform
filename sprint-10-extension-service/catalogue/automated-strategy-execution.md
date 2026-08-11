# Automated strategy execution

A customer configures a rule once, and the platform trades it for them. Buy fifty
of an instrument when its price falls through a level. Sell the holding when it
rises through another. The customer is asleep, the condition is met, and the order
is placed without anyone confirming it.

That is the whole feature, and it is also the reason every control in this brief
is load-bearing rather than hardening added after a demonstration works. A defect
here does not render the wrong number on a screen. It spends a customer's money.

## Who uses it

The customer, in the Angular application: creating a strategy, seeing whether it
is enabled, reading what it has done and why, and turning it off. An operator
needs the last of those too, and needs it to work immediately.

## What it integrates with

| Surface | How this service uses it |
|---|---|
| `market-data` | Consume, group `strategy-service`. The price that entry and exit conditions are evaluated against. |
| `trade-events` | Consume, group `strategy-service`. What happened to the orders this service placed, and what the account now holds. |
| Trade REST API `POST /api/v1/orders` | How orders are placed. Authenticated, with a strategy-generated idempotency key. |
| Angular application | Strategy configuration, the enabled state, and the execution log. |

This service does not produce to `orders`. Publishing straight onto the topic
skips the Trade REST API's business rules and its idempotency check, which are
the two things standing between a strategy bug and an unrecoverable position.
Place orders the way the UI places them.

## The API is yours

There is no contract for this extension. Design the API, write it as OpenAPI
before you write the controller, and bring it to your instructor on day one for
review. The platform conventions still bind: the `{errorCode, message}` envelope,
the platform error catalogue extended only where nothing in it fits, and a bearer
token verified by this service itself.

## What makes it worth building

Identity is the first question and it has no obvious answer. A strategy runs when
nobody is logged in, so it cannot borrow a customer's access token: that token
was issued for a request the customer made, and reusing it outside that request
is how a fifteen-minute credential becomes a permanent one. Decide whether the
strategy trades under a service identity scoped to one account, or under
something else, and write the reasoning down. It is the strongest decision log
entry available in this catalogue.

The second is bounding the damage. A strategy with no maximum spend, no maximum
position size and no circuit breaker on repeated failures can place orders until
the cash runs out. The cap is enforced in code, at the point of decision, not
documented as a convention.

The third is state. A strategy that has been disabled must stop placing orders
now, not at the end of its current evaluation cycle. That means checking the flag
where the decision is taken, not caching it at start-up, and it is a live
demonstration at the review.

## Scope for one week

One strategy type with a small fixed vocabulary of conditions, created disabled,
with an explicit maximum spend or maximum position size. Evaluation against
`market-data`. Orders placed through the Trade REST API and appearing on the
customer's normal blotter, indistinguishable from a manual order. An execution
log recording which condition fired and which order identifier came back.
Enable and disable, both demonstrated live.

Out of scope unless the rest is finished: paper-trading mode, several concurrent
strategies sharing an account-level cap, and a platform-wide kill switch.

## What to get right

- **Access control.** A strategy belongs to one account. Creating, enabling or
  reading one for a different account is refused on the strength of the verified
  token.
- **Hard caps in code.** Maximum spend, maximum position size, and a stop after
  repeated failures. Demonstrate the cap by trying to trade past it.
- **No customer-supplied expressions.** A rule that is an expression the service
  evaluates is code execution wearing a configuration field. Prefer a fixed set
  of rule types with parameters.
- **Off means off.** Check the enabled flag at the point of decision, and prove
  it live by disabling a strategy mid-cycle.
- **Every order is traceable.** For any order this service placed, the execution
  log says which strategy placed it and which condition fired.

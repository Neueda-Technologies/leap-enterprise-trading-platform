# Trade advice and signals

A customer with a blotter and a priced portfolio still has to decide what to do
next, and the platform gives them nothing to decide with. Market data arrives on
`market-data` every polling interval and is used once, to price a fill, and then
discarded. This extension turns that data into a stated view on an instrument, a
buy, a sell or a hold, with the reason it was generated and the numbers behind
it.

It informs a customer who trades. It does not trade. Keep that boundary sharp:
Automated strategy execution is the extension allowed to act without a human in
the loop, and merging the two removes the one control a customer has over their
own capital.

## Who uses it

The customer, on an instrument page or beside a holding in the portfolio screen:
a direction, a strength, and a sentence saying what produced it. Nothing in this
service is useful if the customer cannot see why the signal says what it says.

## What it integrates with

| Surface | How this service uses it |
|---|---|
| `market-data` | Consume, group `advice-service`. The current price for any signal that reacts to now rather than to yesterday's close. |
| Fauxnance `GET /candles/{symbol}` | Historical end-of-day open, high, low, close and volume. Anything with a lookback window comes from here: a moving average, a volatility estimate, a support level. |
| `trade-events` | Optional, group `advice-service`. What the platform's own customers are doing in aggregate, for a signal that flags unusual volume in an instrument. |
| Trade REST API | Optional, to resolve the instruments an account holds when signals are personalised. |
| Angular application | The signal, its direction, its strength and its stated reason. |

## The API is yours

There is no contract for this extension. Design the API, write it as OpenAPI
before you write the controller, and bring it to your instructor on day one for
review. The platform conventions still bind: the `{errorCode, message}` envelope,
the platform error catalogue extended only where nothing in it fits, and a bearer
token verified by this service itself.

## What makes it worth building

The interesting decisions are about cost and cadence, not about the indicator.

End-of-day candles do not change during the day, so refetching them per request
burns quota for an answer that cannot have moved. Cache them, and be able to say
how long for. Recomputing a signal on every `market-data` tick is expensive and
mostly noise; recomputing on a fixed interval is usually enough. Decide which,
and record the reasoning.

The second decision is what a signal is allowed to claim. A generated number
presented as a recommendation is a product and legal problem before it is an
engineering one. The service states its own limitation in the response, and the
UI renders it.

## Scope for one week

One methodology, computed from real Fauxnance candles, for the instruments an
account holds or watches, exposed on a route the Angular application reads and
renders with its reason. A recomputation cadence you chose deliberately, with
candle history cached.

Out of scope unless the rest is finished: backtesting, multiple competing
methodologies, and any machine-learned model. A signal nobody can explain is
worth less here than a moving-average crossover somebody can defend.

## What to get right

- **Access control.** As soon as signals are personalised to an account's
  holdings, the account comes from the verified token and never from a query
  parameter the caller supplies.
- **Quota.** Cache and rate-limit candle fetches per instrument. Every service on
  the platform shares the same daily allowance, so exhausting it here degrades
  the portfolio valuation and the Trade Executor as well.
- **No hardcoded signals.** A value that does not move when the market moves is
  not a signal, and the demonstration is a comparison of two computations taken
  a sensible interval apart.
- **Say what it is.** The response states that the signal is generated and is not
  advice from a licensed adviser.

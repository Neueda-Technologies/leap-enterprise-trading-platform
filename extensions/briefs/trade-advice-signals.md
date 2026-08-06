# Trade advice and signals

## Purpose

A customer with a blotter and a priced portfolio still has to decide what to do
next. This extension turns market data the platform already collects into a
generated signal, a buy, sell or hold view on an instrument, with a stated reason. It
does not place trades; it informs a customer who does. Keep that boundary sharp,
because automated strategy execution is the extension that is allowed to act on a
signal without a human in the loop, and conflating the two removes the one control a
customer has over their own capital.

## Suggested architecture

Consume `trade-events` and `market-data`, group `advice-service`. Use `market-data`
for the live price and `trade-events` if signals should react to what the platform's
own customers are doing in aggregate, for example flagging unusually high sell
volume in an instrument.

Call Fauxnance `GET /candles/{symbol}` for historical end-of-day OHLCV to compute
anything that needs a lookback window: a moving average, a volatility estimate, a
support or resistance level. This is a metered call against the same daily quota
everything else shares; cache candle history rather than refetching it on every
signal recomputation, since end-of-day data does not change intraday.

Decide, and document, how often a signal recomputes: on every `market-data` tick is
expensive and mostly noise, on a fixed interval (every few minutes) is usually
enough for anything derived from end-of-day candles plus a current quote.

## Suggested endpoints

| Method and path | Purpose |
|---|---|
| `GET /api/v1/signals/{symbol}` | The current signal for one instrument: direction, strength, reason |
| `GET /api/v1/signals?accountId={id}` | Signals for the instruments the account holds or watches |
| `GET /api/v1/signals/{symbol}/history` | Past signals for one instrument, for a team that wants to show a track record |

## Data it owns

Generated signals and the indicator values behind them. Does not own instrument
reference data or candles themselves; both are fetched, not owned.

## Security considerations

- **OWASP A01, broken access control**, if signals are personalised to an account's
  holdings (`?accountId=`) rather than instrument-only. Apply the same JWT-claim
  check as every other extension.
- **OWASP A04, insecure design.** A signal is not investment advice, and the service
  must not present it as a guarantee. This is a product and legal concern as much as
  a security one, but it belongs in the acceptance criteria: state clearly, in the
  response and in the UI, that a signal is generated and not a recommendation from a
  licensed adviser.
- Rate-limit or cache Fauxnance candle calls per instrument. An unbounded per-request
  candle fetch across many customers watching the same symbol burns quota fast, and
  quota exhaustion here degrades every other Fauxnance-dependent extension too if
  keys are shared.

## Acceptance criteria a team must demo

- A signal for a real instrument, computed from actual Fauxnance candle data, not a
  hardcoded or random value.
- The signal changes when the underlying data changes, demonstrated by comparing two
  computations a reasonable interval apart.
- The service states its own limitation: no signal is generated as financial advice,
  visible in the API response.

## Stretch goals

- More than one signal methodology (moving-average crossover and a volatility-based
  signal, for instance), with the response indicating which one produced it.
- A backtest endpoint: given historical candles, what would this signal have said,
  and how would it have performed.
- Signal-triggered watchlist alerts, integrating with the watchlists extension for a
  team that has built both.

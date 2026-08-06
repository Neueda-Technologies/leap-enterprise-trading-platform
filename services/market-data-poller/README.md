# Market-data poller

Reference implementation, Sprint 7. Instructor material.

## Why this service exists

The curriculum promises a real-time price stream. Fauxnance does not have one. It serves end-of-day
candles and delayed quotes over HTTP, with no WebSocket and no server-sent events. See
`docs/DECISIONS.md`, decision 2.

So the stream has to be manufactured, and this is what manufactures it. The poller calls the batch
quotes endpoint on an interval and publishes each quote onto `market-data`. Without it that topic is
empty, and every Sprint 10 extension that reads prices, Watchlists and Price Alerts, Trade Advice
and Signals, Automated Strategy Execution, has nothing to consume.

It is also the smallest complete producer in the platform. One responsibility, one topic, no
database. That makes it the right place for a participant to see what a Kafka producer configuration
actually costs.

## What it does

1. Splits the configured symbol list into groups of at most 25.
2. Calls `GET /quotes?symbols=A,B,C` once per group, retrying transient failures with exponential
   backoff and counting every call against a local daily budget.
3. Publishes one message per symbol to `market-data`, keyed by symbol.
4. Sleeps for the remainder of the interval and repeats, until SIGTERM or SIGINT.

One message per symbol, never one per batch. Batching the HTTP call is a quota optimisation.
Batching the Kafka message would put several symbols behind one key, which breaks the per-symbol
ordering the topic contract promises and stops a consumer from filtering to the instruments it cares
about.

## The quota arithmetic

Each key allows 2000 requests per day and the counter resets at 00:00 UTC. That number constrains
the design, and it is meant to.

One batch call covers up to 25 symbols and costs one request, whatever the symbol count. The seeded
set is eight symbols, so one poll is one request.

| Interval | Polls per hour | Requests for a 24 hour run | How long 2000 requests last |
|---|---|---|---|
| 15s, the floor | 240 | 5760 | 8 hours 20 minutes |
| 30s, the default | 120 | 2880 | 16 hours 40 minutes |
| 60s | 60 | 1440 | A full day, with 560 to spare |
| 120s | 30 | 720 | A full day, with 1280 to spare |

Three conclusions follow, and each one is worth stating to a team before they lose a key.

**Batch, or lose the day before lunch.** Eight symbols fetched one at a time at 30 second intervals
is 23040 requests a day. The quota is gone in 2 hours and 5 minutes. The same data, batched, is
2880 requests, and the batch call is the difference between an 8x and a 25x saving depending on how
many instruments the platform holds.

**The default interval does not survive being left running overnight.** At 30 seconds the poller
alone spends the whole quota in 16 hours 40 minutes. That is deliberate: 30 seconds is right for a
taught day, which costs about 960 requests over 8 hours and leaves the rest for the Trade Executor.
Stop the container when the session ends, or set `POLL_INTERVAL_SECONDS=60`, which is the largest
interval that fits a continuous 24 hour run inside the quota.

**The key is shared.** The Trade Executor prices every fill against the same key, and in Sprint 10
the Portfolio service prices every valuation against it. A poller that spends 2880 requests leaves
nothing for either. `DAILY_REQUEST_BUDGET` exists for that: set it to 1200 and the poller stops
calling once it has spent its share, rather than taking the executor's.

The floor of 15 seconds is enforced in code, not documented and hoped for. Below it no configuration
of this service survives even a half-day session, and the quotes are delayed anyway, so polling
faster than the data changes buys nothing but requests.

Check what a key has spent with `GET /usage`, which reports `dailyQuota`, `usedToday` and
`resetsAt`. Use it before assuming Fauxnance is broken.

## Message format

Exactly the `market-data` contract in `docs/contracts/kafka-topics.md`. The key is the symbol.

```json
{
  "eventId": "3a5c7e91-2b4d-4f60-8c1e-9d0f2a4b6c8e",
  "eventType": "QUOTE",
  "eventTime": "2026-09-28T09:15:00Z",
  "source": "market-poller",
  "schemaVersion": 1,
  "payload": {
    "symbol": "AAPL",
    "price": 232.71,
    "currency": "USD",
    "change": 0.21,
    "changePercent": 0.09,
    "previousClose": 232.50,
    "marketState": "open",
    "stale": false,
    "quoteAsOf": "2026-09-28T09:14:58Z"
  }
}
```

`eventTime` is when this process published. `quoteAsOf` is when Fauxnance observed the price. They
differ, and the difference matters: a strategy service acting on `eventTime` is acting on a price
older than it thinks.

`marketState` is passed through untouched, including `closed`. The poller does not decide what an
open market is. `stale` comes from the batch entry, where Fauxnance puts it beside the quote rather
than inside it.

## Never failing on one bad symbol

A market-data feed that exits is worse than one that is wrong, because a dead process is silent.
Four layers keep this one alive.

| Failure | Behaviour |
|---|---|
| One symbol returns an error entry | Logged with the symbol, counted as failed, the rest of the batch is published |
| One symbol returns a quote with no price | Same. Publishing a null price would break every consumer's arithmetic |
| The whole batch call fails | Retried with exponential backoff up to `MAX_ATTEMPTS`, then abandoned for this cycle. The next cycle tries again |
| A batch is abandoned | The next batch in the same cycle still runs |
| Kafka rejects one message | Logged, the remaining symbols are still published |
| Anything unforeseen | Caught at the top of the loop, logged with a stack trace, the loop continues |

A 429 is not retried. The quota does not refill inside a retry window, and three retries on a spent
quota is three more failures in the log.

## Graceful shutdown

SIGTERM and SIGINT set an event. The current cycle finishes, the producer is flushed, the health
server stops and the process exits 0. `docker stop` sends SIGTERM and waits ten seconds before
killing the container, so a process that ignores the signal is killed part way through a publish.

Every sleep in the service waits on that same event, so shutdown does not have to wait out a
60 second interval or a 32 second backoff.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `FAUXNANCE_API_KEY` | none, required | The process refuses to start without it |
| `FAUXNANCE_BASE_URL` | `https://y4t9nq2bqf.execute-api.eu-west-2.amazonaws.com/v1` | |
| `MARKET_DATA_SYMBOLS` | `AAPL,MSFT,GOOGL,AMZN,TSLA,NVDA,JPM,SPY` | Comma separated. Trimmed, upper-cased, deduplicated |
| `POLL_INTERVAL_SECONDS` | `30` | Raised to 15 if set lower |
| `KAFKA_BOOTSTRAP_SERVERS` | `localhost:9092` | `kafka:29092` inside the Compose network |
| `MARKET_DATA_TOPIC` | `market-data` | |
| `REQUEST_TIMEOUT_SECONDS` | `5` | |
| `MAX_ATTEMPTS` | `3` | Attempts per batch, counting the first. Each one costs a request |
| `BACKOFF_INITIAL_SECONDS` | `1` | Doubles per attempt |
| `BACKOFF_MAX_SECONDS` | `60` | |
| `DAILY_REQUEST_BUDGET` | `2000` | Lower it to reserve quota for the executor |
| `HEALTH_PORT` | `8083` | |
| `LOG_LEVEL` | `INFO` | |

## Health

`GET http://localhost:8083/health` returns the poll state. It carries no key and no credential.

```json
{
  "status": "ok",
  "symbols": ["AAPL", "MSFT"],
  "pollIntervalSeconds": 30.0,
  "lastPollAt": "2026-09-28T09:15:00Z",
  "lastSuccessAt": "2026-09-28T09:15:00Z",
  "quotesPublished": 128,
  "requestsUsedToday": 16,
  "requestsRemainingToday": 1984
}
```

`status` is `starting` until the first quote is published, `degraded` when the last success is older
than three intervals, and `ok` otherwise. A degraded poller still answers 200: restarting a container
that is publishing slowly makes it publish nothing at all for the length of the restart.

## Logging

One JSON object per line, on stdout. Filter it with `jq`:

```bash
docker logs -f market-data-poller | jq 'select(.level != "DEBUG")'
docker logs market-data-poller | jq -r 'select(.requests_used) | .requests_remaining_today'
```

## Running it

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
export FAUXNANCE_API_KEY=your-key
PYTHONPATH=src python -m market_data_poller
```

With Docker:

```bash
docker build -t market-data-poller:1.0.0 .
docker run --rm -p 8083:8083 \
  -e FAUXNANCE_API_KEY=your-key \
  -e KAFKA_BOOTSTRAP_SERVERS=kafka:29092 \
  -e POLL_INTERVAL_SECONDS=60 \
  market-data-poller:1.0.0
```

Confirm quotes are arriving:

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic market-data \
  --property print.key=true --from-beginning --max-messages 8
```

## Tests

```bash
pip install -r requirements-dev.txt
pytest
```

49 tests, no network and no broker. The HTTP session and the Kafka producer are hand-written fakes in
`tests/conftest.py`, injected through the constructor. `kafka` is imported inside
`QuotePublisher.create` rather than at module scope, so every other line in `publisher.py` is
testable without the library present.

| File | Covers |
|---|---|
| `test_config.py` | Defaults, symbol parsing, the interval floor, bad values naming themselves |
| `test_fauxnance.py` | Batch request shape, per-symbol errors, quota and transport failures |
| `test_publisher.py` | The envelope against the topic contract, one message per symbol, keying |
| `test_poller.py` | Batching at 25, backoff, budget enforcement, surviving every failure |
| `test_quota.py` | Consumption, refusal at the limit, the 00:00 UTC reset |

## What participants rebuild in Sprint 7

This service is the answer key. Participants write their own, and it is one of the smaller Sprint 7
deliverables, sitting beside the topics, the Trade Executor and the batch ETL.

What they must produce:

- A poller that reads its symbol list from configuration rather than a literal in the code.
- Batched calls of at most 25 symbols, with the quota arithmetic written down. The arithmetic is the
  assessed part, not the code. A team that cannot say how long their interval makes a key last has
  not met the criterion.
- One message per symbol on `market-data`, keyed by symbol, matching the envelope in
  `docs/contracts/kafka-topics.md` field for field.
- A process that survives a bad symbol and a Fauxnance outage.
- Tests with the HTTP and Kafka layers faked.

Where teams go wrong, in the order the errors usually appear:

| Error | What it looks like | What it costs |
|---|---|---|
| One request per symbol | A loop over symbols calling `/quotes/{symbol}` | The key is exhausted the same morning |
| One message per batch | A single Kafka message carrying an array of quotes | Per-symbol ordering is gone and consumers cannot filter |
| Keying by nothing | `producer.send(topic, value)` with no key | Round-robin partitioning, so a symbol's quotes arrive out of order |
| Publishing the poll time as the observation time | `quoteAsOf` set to `datetime.now()` | Every downstream signal is computed on a price that is older than it claims |
| Exiting on the first error | An uncaught exception in the loop | The feed stops and nothing says so |
| The key in the repository | A default value in the source | The finding a security review is supposed to catch, and the reason for rule two in `DECISIONS.md` |

Let a team hit the quota limit once. The 429, and the `Retry-After` header counting down to midnight
UTC, teaches the constraint faster than a warning does.

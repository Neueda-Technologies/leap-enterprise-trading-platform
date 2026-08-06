# Trade Executor

Reference implementation, Sprint 7. Instructor material.

## Why this service exists

There is no broker simulator in this platform, and there will not be one. See `docs/DECISIONS.md`,
decision 1. The Trade Executor is the execution venue: it is the only component that decides whether
an order fills, at what price, and what that does to an account's cash and holdings.

Removing it breaks the property Sprint 7 is built to teach. Until Sprint 7, `POST /api/v1/orders`
validates, fills, writes and returns inside one HTTP request, which works only because nothing real
is happening. Real execution takes time, fails part way, and has to survive the service that
requested it restarting mid-flight. Splitting acceptance from execution is what makes those failure
modes visible, and this service is the half that executes.

## What it does with one order

1. Consumes an `ORDER_PLACED` message from `orders`, group `trade-executor`.
2. Loads the order row from Postgres. Any status other than `NEW` means a previous delivery already
   settled it, so the message is dropped and nothing is published.
3. Pauses for the simulated execution latency.
4. Checks that the instrument is still tradable, then fetches a quote from the Fauxnance API.
5. Applies the fill rules to the quote and the order's limit price.
6. Settles in one transaction: guarded status transition, cash movement under the optimistic lock,
   position upsert.
7. Publishes `ORDER_FILLED` or `ORDER_REJECTED` to `trade-events`, keyed by `accountId`.
8. Acknowledges the offset.

The order of steps 6, 7 and 8 is the contract's, not a preference. Publishing before the commit
risks an event for a transaction that rolled back, which nothing can undo. Acknowledging before
publishing risks an order that settled in Postgres and told nobody.

## Fill rules

The contract fixes the message shape and the business rules. It does not fix the pricing, which
`docs/DECISIONS.md` leaves as a design decision. These are the decisions this implementation makes,
and every one of them is in `FillPolicy` or `OrderExecutionService` where it can be read and
argued with.

| Rule | Behaviour | Reasoning |
|---|---|---|
| Marketability | A BUY fills when the quote is at or below its limit price. A SELL fills when the quote is at or above it. | The status enumeration has no working state between `NEW` and terminal, so there is nowhere to rest an unmarketable order. It is rejected, not held. |
| Fill price | BUY fills at the lower of the limit price and the quote. SELL fills at the higher. | Under the marketability gate both reduce to the quote, which is the intended outcome: the customer gets the market price, not the price they were willing to accept. The min and max form is the invariant that survives a later sprint adding market orders. |
| Rounding | The quote is rounded to two decimal places, half up, before it is compared or stored. | `NUMERIC(18,2)` cannot hold what Fauxnance returns. Rounding after the limit check would let an order fill at a price that failed its own check. |
| Quantity | Fill in full or reject. | There is no partial-fill status. |
| Rules 6 and 7 | Re-checked at execution time, against the fill price and against the balance as it is now. | The Trade REST API checked them at acceptance, against the limit price and an older balance. Both move while the order sits on the topic. |
| Account status | An account that is no longer `ACTIVE` rejects the order. | Suspension has to stop trading, including orders accepted before the suspension. |
| Market state | Passed through, not used as a gate. | Fauxnance serves a price when the market is closed, and a cohort demonstrating at 15:00 in Dublin or 10:00 in Bangalore needs fills to happen. A team that wants a closed-market rejection should add it and say so. |

### Rejection reasons

Written to `orders.reject_reason` and copied onto the event as `reason`. The first four come from the
topic contract's examples. The last three are added, because each one names a state that only exists
once execution is asynchronous.

| Reason | Cause | Source |
|---|---|---|
| `PRICE_NOT_MET` | The quote is outside the limit price. | Contract |
| `INSTRUMENT_NOT_TRADABLE` | The instrument was suspended after the order was accepted. | Contract |
| `INSUFFICIENT_FUNDS` | Cash at execution time does not cover the fill. | Contract |
| `PRICING_UNAVAILABLE` | Fauxnance returned nothing usable after the retry budget was spent. | Added |
| `INSUFFICIENT_HOLDINGS` | The holding was sold by another order first. | Added |
| `ACCOUNT_NOT_ACTIVE` | The account was suspended or closed after the order was accepted. | Added |

`PRICING_UNAVAILABLE` is the executor's analogue of `MKT-503` in the platform error catalogue,
which the Portfolio contract defines as pricing unavailable. The alternative, leaving the order at
`NEW` until a price appears, is worse: the customer sees an order that never resolves and the
blotter has no way to explain it.

`CANCELLED_BY_CUSTOMER` is not in the enum. Cancellation is the Trade REST API's transition.

## Idempotency

The platform runs at-least-once, so duplicates happen and are not worth trying to eliminate. This
service uses the guarded state transition, mechanism 2 in the topic contract:

```sql
UPDATE orders
   SET status = 'FILLED', executed_price = ?, executed_on = ?
 WHERE id = ? AND status = 'NEW'
```

Zero rows affected means another delivery got there first. The statement runs before any cash moves,
inside the same transaction, so a duplicate returns having changed nothing. There is no
processed-events table and none is needed.

This is the Sprint 7 acceptance demonstration. Replay a consumed `ORDER_PLACED` message and show the
cash balance does not move twice:

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic orders \
  --from-beginning --max-messages 1 > order.json

kafka-console-producer.sh --bootstrap-server localhost:9092 --topic orders \
  --property parse.key=true --property key.separator=: < order.json
```

The log line to look for is `Order ... is already FILLED. Skipping duplicate delivery.` The balance
in `accounts` is unchanged and no second event appears on `trade-events`.

## Atomicity and the optimistic lock

The status change, the cash movement and the position write are one transaction. If any of the three
fails, none of them happened. The cash update carries the version that was read at the start of the
transaction:

```sql
UPDATE accounts
   SET cash_balance = ?, version = version + 1, last_updated = ?
 WHERE id = ? AND version = ?
```

Zero rows affected means another writer moved first. That is not a failure: the transaction rolls
back and the executor re-reads and tries again, up to `executor.optimistic-lock.max-attempts`. Only
an exhausted budget is an error, and it fails the message so that Kafka redelivers it. This is
non-functional requirement NFR-02 and it is why `accounts.version` exists.

Three listener threads run against three partitions, so two orders on the same account are never
processed concurrently: they share a key and therefore a partition. The optimistic lock is there for
the writers the executor does not control, which are the Trade REST API and, in Sprint 10, the
Portfolio service.

## Failure handling and the dead-letter topic

Two failure classes, handled differently.

| Class | Example | Handling |
|---|---|---|
| Will never succeed | Malformed JSON, a missing `orderId`, an `orderId` that is not in Postgres, an unexpected `eventType` | `NonRetryableMessageException`, dead-lettered on the first attempt |
| Will succeed later | Kafka broker unreachable, database connection lost, optimistic lock budget exhausted | Retried with exponential backoff, dead-lettered once `executor.max-delivery-attempts` is spent |

The dead-letter topic is `orders.DLT`, per the contract. Spring's default suffix is `-dlt`, so
`KafkaConsumerConfig` overrides it. The original message is the value and the failure reason is in
the headers Spring adds.

A Fauxnance outage is deliberately not in either row. It is retried inside the quote client, and if
the budget is spent the order is rejected with `PRICING_UNAVAILABLE`. A price feed that is down is a
business outcome, not a message-processing failure, and dead-lettering the order would leave it at
`NEW` for ever.

## Fauxnance usage

The executor calls `GET /quotes/{symbol}`, one symbol at a time, because it prices one order at a
time. Two things keep that inside the 2000 requests per day quota, which it shares with the
market-data poller and anything else using the same key.

Quotes are cached per symbol for `fauxnance.quote-max-age`, five seconds by default. A burst of ten
orders on AAPL inside one second costs one request rather than ten. Failures are never cached, so
one transient error does not reject every order on that symbol for the length of the window.

Transient errors are retried with backoff. A 404 is not retried, because a symbol Fauxnance does not
know will still be unknown on the next attempt. A 429 is not retried either, because the quota does
not refill inside the retry window; the log line names the cause and points at `GET /usage`. A 202
is retried, because it means Fauxnance is backfilling the symbol and will have a price shortly.

The key comes from `FAUXNANCE_API_KEY` and never from a file in the repository.

## Simulated execution latency

Fauxnance answers in tens of milliseconds and Postgres in single milliseconds. Without a delay, the
blotter reaches `FILLED` before the operator lets go of the mouse button, the demo looks exactly like
the synchronous Sprint 6 behaviour, and the reason for the whole sprint is invisible.

`executor.latency.min` and `executor.latency.max` default to 250ms and 750ms. The delay is well
inside `max.poll.interval.ms`, so it does not provoke a rebalance. Set both to `0s` in an
integration test.

## Configuration

Everything is an environment variable. Nothing sensitive has a default.

| Variable | Default | Purpose |
|---|---|---|
| `DB_URL` | `jdbc:postgresql://localhost:5432/trading` | Operational database |
| `DB_USERNAME` | `trading_app` | The least-privilege application role, not the owner |
| `DB_PASSWORD` | none | Never committed |
| `KAFKA_BOOTSTRAP_SERVERS` | `localhost:9092` | `kafka:29092` inside the Compose network |
| `ORDERS_TOPIC` | `orders` | |
| `TRADE_EVENTS_TOPIC` | `trade-events` | |
| `MAX_DELIVERY_ATTEMPTS` | `4` | Attempts before `orders.DLT`, counting the first |
| `EXECUTION_LATENCY_MIN` | `250ms` | |
| `EXECUTION_LATENCY_MAX` | `750ms` | |
| `FAUXNANCE_BASE_URL` | `https://y4t9nq2bqf.execute-api.eu-west-2.amazonaws.com/v1` | |
| `FAUXNANCE_API_KEY` | none | Per-student key. The service logs a warning and rejects every order without it. |
| `QUOTE_MAX_AGE` | `5s` | Cache window per symbol |

The service listens on 8082 and exposes `/actuator/health`.

## Running it

Postgres must have the Sprint 3 schema and the Sprint 7 additions applied, and the three topics must
exist with the partition counts in the topic contract.

```bash
export FAUXNANCE_API_KEY=your-key
export DB_PASSWORD=your-password
mvn spring-boot:run
```

With Docker:

```bash
docker build -t trade-executor:1.0.0 .
docker run --rm -p 8082:8082 \
  -e DB_URL=jdbc:postgresql://postgres:5432/trading \
  -e DB_PASSWORD=your-password \
  -e KAFKA_BOOTSTRAP_SERVERS=kafka:29092 \
  -e FAUXNANCE_API_KEY=your-key \
  trade-executor:1.0.0
```

The image is multi-stage. Maven and the JDK stay in the build stage; the runtime stage is a JRE, the
jar and an unprivileged user.

## Tests

```bash
mvn test
```

54 tests, no database, no broker and no network. The repository is mocked and the HTTP layer is
faked, because what is being tested is the decision logic, not Postgres.

| Class | Covers |
|---|---|
| `FillPolicyTest` | Marketability, fill price, rounding, weighted average cost |
| `OrderExecutionServiceTest` | Every fill and reject path, the guarded transition, optimistic-lock retry |
| `CachingQuoteClientTest` | Cache window, per-symbol independence, failures not being cached |
| `FauxnanceQuoteClientTest` | Which Fauxnance status codes cost a retry and which do not |
| `OrderPlacedListenerTest` | Parsing, unknown-field tolerance, publish before acknowledge, poison messages |
| `TradeEventSerialisationTest` | The `trade-events` wire format against the topic contract |
| `TradeExecutorApplicationTests` | The Spring context wires, and the defaults match this README |

The three tests worth reading first are `losingTheGuardedTransitionToAConcurrentDeliveryMovesNoMoney`,
`anUnavailableQuoteRejectsTheOrderRatherThanLeavingItWorking` and
`aLostLockIsRetriedAndTheSecondAttemptSucceeds`. They are the three properties a participant has to
be able to defend.

## What is deliberately not here

| Not implemented | Why |
|---|---|
| Partial fills | No order status represents one |
| Resting orders | Same reason. An unmarketable order is rejected |
| Consuming `market-data` for a cached last price | The topic contract marks it optional. The five-second quote cache already covers the quota problem, and pricing a fill from a topic adds a second source of truth for the same number |
| Kafka transactions | The side effects are database writes, not topic writes. The guarded transition gives the same outcome with less machinery |
| TLS, SASL and ACLs on the broker | Local development runs plaintext, per the topic contract. Document the production configuration; do not claim it is implemented |

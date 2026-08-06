# Trading domain engine

Sprint 5 deliverable. Reference implementation.

## Why this module exists

The rules that decide whether a trade may happen outlive every technology around them. In Sprint 6 they are called from a Spring controller inside one HTTP request. In Sprint 7 the same rules are called from a Kafka consumer running in a different process, minutes later, against a price that did not exist when the order was placed. If those rules live in a controller, the Trade Executor has to reimplement them, and the two copies drift. The first time they drift, the platform accepts an order the executor then refuses, and the customer sees an order stuck in `NEW` forever.

So the rules live here, in a library with no database, no HTTP and no framework. It compiles against one dependency, `jakarta.validation-api`, and its whole test suite runs in under five seconds because there is nothing to start.

The other consequence is testability. Every business rule below is proved with plain objects. A rule that cannot be tested without a running Postgres is a rule nobody will test.

## What is in it

| Type | Kind | Responsibility |
|---|---|---|
| `Account` | entity | Cash balance, status, optimistic lock version. `debit`, `credit`, `isActive`, `canAfford`. |
| `Instrument` | entity | Reference data. `isTradable` is business rule 3. |
| `Order` | entity | Intent to trade, in any status. Transitions `fill`, `reject`, `cancel`. |
| `Position` | entity | Net holding. `apply` moves it, `marketValue` values it at a supplied price. |
| `Money` | value helper | `BigDecimal` at scale 2, `HALF_UP`. The one place rounding is decided. |
| `AccountStatus` | enum | `ACTIVE`, `SUSPENDED`, `CLOSED`. |
| `OrderSide` | enum | `BUY`, `SELL`. |
| `OrderStatus` | enum | `NEW`, `FILLED`, `REJECTED`, `CANCELLED`. |
| `PlaceOrderRequest` | DTO | Bean Validation constraints matching `contracts/trade-api.yaml`. |
| `OrderPlacementService` | domain service | Business rules 1 to 8, in the contract's order. |
| `SettlementService` | domain service | Business rules 9 and 10. Moves cash and position together, or moves neither. |
| `Settlement` | record | What a settlement moved. Maps one to one onto the `trade-events` payload. |
| `IdempotencyKeyRegistry` | port | A seam for rule 8 so it can be tested without a database. Read its javadoc before implementing it. |
| `TradingException` and subtypes | exceptions | One type per business rule failure, each carrying its catalogue code. |

## Business rules

Evaluated in this order by `OrderPlacementService.placeOrder`. The first failure wins and no later rule runs. The order is part of the contract: it decides which code a request that breaks two rules receives, and the Angular UI branches on that code.

| # | Rule | Exception | Code |
|---|---|---|---|
| 1 | The account must exist | `AccountNotFoundException` | `ACC-404` |
| 2 | The account must be `ACTIVE` | `AccountNotActiveException` | `ACC-403` |
| 3 | The instrument must exist and be tradable | `InstrumentNotFoundException` | `INS-404` |
| 4 | Quantity must be greater than zero | `InvalidOrderException` | `VAL-422` |
| 5 | Price must be greater than zero | `InvalidOrderException` | `VAL-422` |
| 6 | BUY: cash balance at least quantity times price | `InsufficientFundsException` | `ORD-400` |
| 7 | SELL: held quantity at least the order quantity | `InsufficientHoldingsException` | `ORD-409` |
| 8 | The idempotency key must be unused | `DuplicateOrderException` | `ORD-409` |
| 9 | Cash and position update atomically | `SettlementService` | none |
| 10 | Every order is recorded, including a rejected one | `SettlementService.reject` | none |

Three points about how the rules are enforced.

Rule 8 is enforced in the Trade REST API by the unique constraint on `orders.idempotency_key`, not by a read followed by a write. Two concurrent requests carrying the same key both pass a read-then-write check, and the side effect of losing that race is a duplicated trade. `IdempotencyKeyRegistry` exists so the rule can be stated and tested here; the database is the authority.

Rules 9 and 10 are enforced by `SettlementService`, which checks every precondition before it writes the first field. A settlement that is going to fail leaves the account, the position and the order exactly as it found them. Atomicity is finished by the caller's transaction, but it starts here: an object graph that has already been half mutated depends on someone remembering to roll back.

Rules 4 and 5 are checked twice. `PlaceOrderRequest` carries Bean Validation constraints, which the Trade REST API runs as a syntactic gate before the service is reached, and `OrderPlacementService` checks them again. The duplication is deliberate. The domain has to hold for a caller that never ran a validator, for example the Trade Executor replaying an order off the `orders` topic.

## Exception hierarchy

All exceptions extend `TradingException`, which is unchecked and carries a catalogue `errorCode`. It carries no HTTP status: the domain has no opinion about HTTP, and the Trade REST API maps codes to statuses in one place, its `@ControllerAdvice`.

Exception messages are the catalogue message and nothing more. Account keys, symbols and amounts are held as typed fields for logging and never appear in the message, because the message becomes the response body. Leaking internal detail there is OWASP A05.

The Sprint 5 specification names six exceptions. This module ships nine. The three additions, and why:

| Addition | Code | Why |
|---|---|---|
| `InvalidOrderException` | `VAL-422` | Rules 4 and 5 are business rules with an error code, and the specification's list has no member for them. Without it, both rules would be enforceable only through Bean Validation, which a non-Spring caller never runs. |
| `OrderNotCancellableException` | `ORD-409` | `DELETE /api/v1/orders/{id}` returns `ORD-409` for an order that is already terminal. The state transition belongs on `Order`, so the refusal needs a type. |
| `OrderNotFoundException` | `ORD-409` | The same endpoint returns 404 for an unknown order, with error code `ORD-409`. The catalogue is a closed enumeration with no order-not-found code, so status and code must be carried separately. |

The six specified exceptions are unchanged in name, meaning and code.

## Design decisions worth arguing about

**Entities are mutable, values are not.** `Account.debit` changes a balance rather than returning a new account. An account is an entity with a lifetime and an identity, and pretending otherwise would mean the persistence layer reassembling it on every write. `Money`, `Settlement` and `PlaceOrderRequest` are values and are immutable.

**Money is `BigDecimal` at scale 2, never `double`.** Binary floating point cannot represent 0.10 exactly. `AccountTest` debits 0.10 a thousand times from 100.00 and asserts the balance is exactly zero, which is the test a `double` implementation fails.

**Time is a parameter, never `Instant.now()`.** Every method that records a time takes it as an argument. A domain that reads the system clock cannot be tested deterministically, and the time recorded in the database must be the same value that reaches Kafka.

**`Position.marketValue` requires a price.** The domain performs no I/O, so it cannot fetch a quote. A valuation that silently used a stale cached price would be worse than no valuation. The Trade REST API never calls it; the Sprint 10 Portfolio and P&L extension does, with a live Fauxnance quote.

**The average cost rule is asymmetric.** A buy recalculates the weighted average. A sell reduces the quantity and leaves the average alone. Keeping the cost basis intact through a sale is what makes realised profit and loss computable at the point of sale.

## Building and testing

Java 21 and Maven 3.9 or later.

```bash
mvn test        # run the suite
mvn install     # publish to the local repository, required before building trade-api
```

The Trade REST API resolves this module from the local Maven repository as `com.tradingplatform:trading-engine:1.0.0`. There is no aggregator POM, so `mvn install` here must run before `mvn package` there.

## Tests

The suite is written test first. Red, green, refactor, evidenced in the commit history.

| Test class | Covers |
|---|---|
| `AccountTest` | Status, debit, credit, affordability, money scale and drift, the optimistic lock version. Includes `testDebit_InsufficientFunds`. |
| `InstrumentTest` | `isTradable`, suspension without deletion, identity by symbol. |
| `OrderTest` | Notional value, consideration at an executed price, every status transition and every refused transition. |
| `PositionTest` | Weighted average cost on a buy, cost basis preserved on a sell, market value, guards. Includes `testSell_InsufficientHoldings`. |
| `OrderLogicTest` | Business rules 1 to 8, each fired and each not fired, plus the evaluation order itself. Includes `testReject_InactiveAccount`. |
| `SettlementServiceTest` | Cash and position moving together, nothing applied when a precondition fails, rejection and cancellation as outcomes. |
| `PlaceOrderRequestValidationTest` | Every Bean Validation constraint, including the Fauxnance symbol scheme and two-decimal prices. |

`AccountTest`, `OrderLogicTest` and `PlaceOrderRequestValidationTest` are named in the Sprint 5 acceptance criteria and must be green.

## Configuration

None. The module reads no environment variable, no property file and no system clock. That is the point of it.

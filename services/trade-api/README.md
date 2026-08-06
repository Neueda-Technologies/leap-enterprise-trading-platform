# Trade REST API

Sprint 6 deliverable. Reference implementation of `docs/contracts/trade-api.yaml`.

## Why this service exists

An order has to be recorded before it has been executed. Execution takes time, it fails, and it must survive the service that requested it restarting mid-flight. Something therefore has to accept the order, prove it is allowed, write it down, and answer the customer, without waiting for the trade to happen. That is this service.

Everything it does not do follows from the same sentence. It does not price an order, it does not call the Fauxnance API, and from Sprint 7 it does not move money. Those belong to the Trade Executor, which runs in another process and reads the order off a topic.

The service is also where the platform's security boundary is drawn. Every route under `/api/**` requires a verified token, and every account key in a request is checked against the token's claim before a row is read.

## Endpoints

Six, exactly as the contract defines them. All require `Authorization: Bearer <jwt>`.

| Method | Path | Returns |
|---|---|---|
| POST | `/api/v1/orders` | The recorded order: `NEW` in asynchronous mode, terminal in synchronous mode |
| DELETE | `/api/v1/orders/{id}` | The cancelled order. `{id}` is the UUID, without the `ORD-` display prefix |
| GET | `/api/v1/accounts/{id}` | Account details, both identifiers and the lock version |
| GET | `/api/v1/accounts/{id}/balance` | Available cash, in the configured base currency |
| GET | `/api/v1/accounts/{id}/positions` | Holdings with a net quantity above zero |
| GET | `/api/v1/accounts/{id}/orders` | The blotter, newest first, optionally filtered by `status`, `from` and `to` |

The live API description is served at `http://localhost:8080/swagger-ui`. It is generated from the running code, so where it disagrees with `docs/contracts/trade-api.yaml` the code has drifted and the code is what to fix.

## Error catalogue

One envelope, `{"errorCode": "...", "message": "..."}`, produced in one place: `GlobalExceptionHandler`. Clients branch on `errorCode`, never on `message` and never on the status alone, because `ORD-409` appears with both 404 and 409.

| Exception | Code | HTTP |
|---|---|---|
| `AccountNotFoundException` | `ACC-404` | 404 |
| `AccountNotActiveException` | `ACC-403` | 403 |
| `AccountAccessDeniedException` | `ACC-403` | 403 |
| `InstrumentNotFoundException` | `INS-404` | 404 |
| `InsufficientFundsException` | `ORD-400` | 400 |
| `InsufficientHoldingsException` | `ORD-409` | 409 |
| `DuplicateOrderException` | `ORD-409` | 409 |
| `OrderNotCancellableException` | `ORD-409` | 409 |
| `ConcurrentUpdateException` | `ORD-409` | 409 |
| `OrderNotFoundException` | `ORD-409` | 404 |
| `InvalidOrderException`, Bean Validation, binding failures | `VAL-422` | 422 |
| `InvalidTokenException`, missing or malformed token | `AUTH-401` | 401 |

No response body carries a stack trace, a SQL fragment, a class name or an internal identifier. The detail is logged. An unexpected exception returns 500 with `errorCode: INTERNAL`, which is deliberately outside the catalogue so that a client branching on the catalogue cannot mistake an outage for a business failure. The contract documents no 500 response.

## Execution mode

The platform passes through two behaviours and this service holds both. The switch is `trading.execution-mode`.

| Mode | Sprint | What happens | Response |
|---|---|---|---|
| `sync` | 6 | Validate, record, settle cash and position, mark the order `FILLED`, all in one transaction. Fill price is the limit price, because there is no quote. Publishes `ORDER_FILLED` to `trade-events`. | `FILLED` |
| `async` | 7 onwards, default | Validate, record as `NEW`, publish `ORDER_PLACED` to `orders` after the commit. | `NEW` |

Keeping `sync` reachable after Sprint 7 is not sentiment. It lets a team run the API without a broker while they are debugging something else, and it turns the difference between the two worlds into a property a participant can toggle and observe.

## How an order is placed

1. The filter verifies the token and puts the identity on the request.
2. `OrderService` checks that the token's `accountId` reaches the account in the body, or returns `ACC-403`.
3. The account, the instrument and the position are loaded.
4. `OrderPlacementService`, from the domain module, applies business rules 1 to 8 in order and returns an order in status `NEW`.
5. The order is inserted. A duplicate `idempotency_key` violates the unique constraint and becomes `ORD-409`.
6. In `sync` mode, `SettlementService` moves cash and position, the account row is updated with `WHERE version = :expected`, the position is upserted, and the order is filled with a guarded transition.
7. The event is published after the transaction commits, never inside it.

Three of those steps are load-bearing and easy to get wrong.

**The unique constraint is business rule 8.** There is no select before the insert. Two concurrent requests carrying the same key both pass a read-then-write check, and the side effect of losing that race is a duplicated trade.

**The optimistic lock is a predicate, not a check.** `UPDATE accounts SET cash_balance = ?, version = version + 1 WHERE id = ? AND version = ?`. Zero rows affected means another transaction won, and the service raises `ORD-409` rather than applying a balance computed from stale data. A lost update has no error, no log line and no symptom until somebody reconciles the cash.

**Publishing happens after the commit.** Publishing inside the transaction risks an event for an order that was then rolled back, and there is no way to recall it. Publishing after risks a committed order that was never published, which is recoverable by replaying from the order table. Choose the recoverable failure. The mechanism is `@TransactionalEventListener(phase = AFTER_COMMIT)` on `KafkaEventPublisher`.

## Kafka

Per `docs/contracts/kafka-topics.md`. Every message carries the five-field envelope plus a payload, keyed by `accountId` as a string so that all events for one account land on one partition and stay ordered.

| Topic | Event type | Published when |
|---|---|---|
| `orders` | `ORDER_PLACED` | An order is accepted in `async` mode |
| `trade-events` | `ORDER_FILLED` | An order is filled in `sync` mode |
| `trade-events` | `ORDER_CANCELLED` | A customer cancels a working order, reason `CANCELLED_BY_CUSTOMER` |

Producer settings are `acks=all`, `enable.idempotence=true`, ten retries and at most five in-flight requests per connection, which keeps ordering within a partition while a retry is outstanding.

A send that fails is logged and does not fail the request. The order is already committed, and turning a broker problem into a 500 would tell a customer their order was refused when it was accepted. Recovery is a sweep over orders left in `NEW` past a threshold, which is worth building once you have seen the failure.

Set `trading.kafka.enabled=false` to run with no broker at all. The publisher bean is then absent and the application event goes nowhere.

## Authentication and authorisation

They are different questions and they are answered in different places.

`JwtAuthenticationFilter` answers the first: is this caller who they say they are. It is mapped by URL pattern onto `/api/*`, so a route added next sprint is protected before anyone writes its controller. HS256, verified against `JWT_SECRET`, checking the signature and the expiry every time. A missing, malformed, expired or wrongly signed token is `AUTH-401` with an identical body in every case, because a more specific message is a free oracle.

The service layer answers the second: may this caller reach this account. It needs the account the request is addressing, which the filter does not have without parsing bodies. A token whose `accountId` claim does not match is `ACC-403`, with the same message a suspended account gets, so that nobody can enumerate account keys by reading which of the two answers came back. A token carrying the `ADMIN` role reaches any account.

The issuer is not pinned by default. The auth contract says consumers must not require a particular value, so that swapping `auth-stub` for `auth-service` in Sprint 8 needs configuration only. Set `JWT_REQUIRED_ISSUER` once the cutover is done.

This service does not use Spring Security. One filter is enough to demonstrate JWT verification, and Spring Security's defaults would have to be switched off one by one before the platform error envelope came out of a failed authentication. The trade is worth naming: adding method-level authorisation, CSRF handling or an OAuth2 resource server later means adopting Spring Security, not extending this filter.

## Persistence

MyBatis, mapper interfaces in `repository`, SQL in `src/main/resources/mapper/*.xml`. Every placeholder is `#{}`, which becomes a JDBC bind parameter and cannot change the shape of a statement. There is no `${}` anywhere in this service.

Result maps use `<constructor>` because the domain entities have no setters. An account whose balance can be set from outside the entity has no invariant left to protect.

Two custom type handlers, both because the defaults are wrong here.

`UuidTypeHandler` binds `java.util.UUID` with `setObject`, so Postgres receives a binary uuid and uses the primary key index instead of a cast. MyBatis has no built-in handler for `UUID`.

`UtcInstantTypeHandler` reads and writes `TIMESTAMP` columns as UTC. MyBatis's own Instant handler goes through `java.sql.Timestamp`, which uses the JVM default zone, so the same row read on a laptop in Dublin during British Summer Time and in a container running UTC produces instants an hour apart. The smaller fix is this handler. The larger fix, in any schema you design yourself, is `TIMESTAMPTZ`.

The position upsert has a Postgres statement using `ON CONFLICT` and an H2 statement using `MERGE`, selected by a MyBatis `databaseId`. The H2 variant exists only so the mapper tests run in a second without Docker. `MyBatisConfig` explains why that is preferred to writing one portable statement that races.

## Running it

The service needs Postgres and, in `async` mode, Kafka. The compose file that starts them is built alongside this service; the defaults here match it.

```bash
# 1. Publish the domain module. There is no aggregator POM.
mvn -f ../trading-engine/pom.xml install

# 2. Run the service.
mvn spring-boot:run
```

Against services on the host rather than in the compose network:

```bash
DB_HOST=localhost KAFKA_BOOTSTRAP_SERVERS=localhost:9092 mvn spring-boot:run
```

Without a broker, which is the Sprint 6 state:

```bash
TRADING_EXECUTION_MODE=sync TRADING_KAFKA_ENABLED=false mvn spring-boot:run
```

Build the image from the `services` directory, not from here, because the build needs both projects:

```bash
docker build -f services/trade-api/Dockerfile -t trade-api:1.0.0 services
```

In `docker-compose.yml` that is `context: ./services` and `dockerfile: ./trade-api/Dockerfile`. The container listens on 8080 and answers `GET /actuator/health` for the health check.

## Testing

```bash
mvn -f ../trading-engine/pom.xml install   # once, before the first run
mvn test
```

104 tests, about twenty seconds, no Docker.

| Test class | Kind | Covers |
|---|---|---|
| `OrderServiceTest` | unit, mocked mappers | Both execution modes, every business rule reaching the caller as its own exception, the optimistic lock, the guarded transitions, authorisation, cancellation and the published payloads. |
| `AccountServiceTest` | unit, mocked mappers | The four read paths, ownership refused before the read, filters passed through to the query. |
| `OrderControllerTest` | slice, `@WebMvcTest` | The request contract and every entry in the error catalogue, including that the body leaks nothing. |
| `AccountControllerTest` | slice, `@WebMvcTest` | Response shapes, query parameter binding, the two-identifier account response. |
| `JwtVerifierTest` | unit | Valid, expired, wrongly signed, unsigned, garbage, missing claims, issuer pinning, and that the failure message never varies. |
| `JwtAuthenticationFilterTest` | unit, mock servlet | Missing header, wrong scheme, forged token, and that the chain does not run. |
| `MapperIntegrationTest` | H2 in PostgreSQL mode | The unique constraint, the optimistic lock predicate, the guarded status transitions, the upsert, the blotter ordering and its filters. |
| `ApplicationContextTest` | `@SpringBootTest`, H2 | The whole context starts, properties bind, the filter is mapped, the publisher disappears when Kafka is off. |

The domain services are the real ones in `OrderServiceTest`. Mocking them would prove the service calls something, which is not the question.

H2 is not Postgres and the mapper tests know it. They are the fast loop while you are writing SQL. The compose stack is the acceptance environment.

## Configuration

Every value is read from an environment variable with a default that works under Docker Compose.

| Environment variable | Property | Default | Meaning |
|---|---|---|---|
| `SERVER_PORT` | `server.port` | `8080` | HTTP port |
| `DB_HOST` | `spring.datasource.url` | `postgres` | Database host, the compose service name |
| `DB_PORT` | `spring.datasource.url` | `5432` | Database port |
| `DB_NAME` | `spring.datasource.url` | `trading` | Database name |
| `DB_USER` | `spring.datasource.username` | `trading_app` | Least-privilege application role, no DDL and no DELETE |
| `DB_PASSWORD` | `spring.datasource.password` | `trading_app` | Development value. Replace it everywhere real |
| `DB_POOL_SIZE` | `spring.datasource.hikari.maximum-pool-size` | `10` | Connection pool ceiling |
| `KAFKA_BOOTSTRAP_SERVERS` | `spring.kafka.bootstrap-servers` | `kafka:9092` | Broker list |
| `KAFKA_ORDERS_TOPIC` | `trading.kafka.orders-topic` | `orders` | Accepted orders awaiting execution |
| `KAFKA_TRADE_EVENTS_TOPIC` | `trading.kafka.trade-events-topic` | `trade-events` | Order lifecycle outcomes |
| `TRADING_KAFKA_ENABLED` | `trading.kafka.enabled` | `true` | `false` removes the publisher and runs with no broker |
| `TRADING_EXECUTION_MODE` | `trading.execution-mode` | `async` | `sync` for Sprint 6 behaviour |
| `TRADING_BASE_CURRENCY` | `trading.base-currency` | `USD` | ISO 4217 code reported on the balance |
| `JWT_SECRET` | `trading.jwt.secret` | development value | HS256 secret, shared with the auth service. At least 32 characters |
| `JWT_CLOCK_SKEW_SECONDS` | `trading.jwt.clock-skew` | `30` | Tolerance on `exp` and `iat` |
| `JWT_REQUIRED_ISSUER` | `trading.jwt.required-issuer` | blank | Blank accepts any issuer. Pin it after the Sprint 8 cutover |

`JWT_SECRET` must match whatever the auth stub or the auth service signs with. The default is a development value and is obviously one.

## Contract points that needed a decision

These are places where the source documents left room, and what this implementation does.

**A 404 that carries `ORD-409`.** `contracts/trade-api.yaml` defines the 404 on `DELETE /api/v1/orders/{id}` with `errorCode: ORD-409`, and the catalogue is a closed enumeration with no order-not-found code. Implemented as written. It is the clearest possible demonstration of why the contract tells clients to branch on the code together with the status.

**Bean Validation runs before the documented rule order.** Rule 1 says a missing account is `ACC-404`, and rule 4 says a bad quantity is `VAL-422`. A request that is both arrives as `VAL-422`, because Bean Validation on the DTO runs before the controller body. Field validation is a syntactic gate; the documented ordering governs the semantic rules evaluated in the service.

**Reads are allowed on a suspended account.** `AccountStatus` says only an `ACTIVE` account may place or cancel orders. Business rule 2 is therefore applied to `POST /api/v1/orders` and `DELETE /api/v1/orders/{id}` and not to the account queries. The 403 on the read routes is the ownership failure. A customer whose account has been suspended has an obvious right to see the balance and the history.

**Balance currency is configured.** `BalanceResponse.currency` is required and `accounts` has no currency column. Inferring one from the instruments an account happens to hold would give a different answer as the holdings change, so it comes from `trading.base-currency`.

**The API publishes to `trade-events`.** The producer matrix in `kafka-topics.md` lists the Trade REST API as a producer to `orders` only. It also lists `trade-api` as a valid `source`, and a customer cancellation arrives at this service and nowhere else, so no other process can publish `ORDER_CANCELLED`. In `sync` mode the API is acting as the executor, so it publishes `ORDER_FILLED` for the same reason. A rejection or a fill that no consumer ever sees is how a fill rate of 100 per cent gets reported.

**`ORD-409` covers a lost optimistic lock.** The catalogue has no code for a concurrency conflict and cannot be extended without breaking the generated Angular client. 409 is the right status and the correct client behaviour is to retry, which is what the schema comment on `accounts.version` already says.

**The order identifier is strict.** `DELETE /api/v1/orders/{id}` takes the bare UUID. The `ORD-` prefix that every response carries is rejected with `VAL-422`, because the contract is explicit that the path parameter does not include it.

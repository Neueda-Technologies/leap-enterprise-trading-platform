# Sprint 6: the Trade REST API

Everything the platform has built so far is unreachable. The schema answers
psql. The rules answer a JUnit test. Neither answers a customer, and no other
service can reach either of them. This sprint is the front door: one HTTP
service that accepts an order, proves the caller is who they claim to be,
applies the rules you wrote in Sprint 5, writes the result to the schema you
designed in Sprint 3, and answers in the shape the Angular application generates
a client from.

It decides nothing about whether a trade is allowed and it prices nothing. It
owns transport and persistence: JSON into a domain call, a domain exception into
a documented error code, one transaction around the work that has to succeed or
fail together. That thinness is not tidiness. In Sprint 7 the same rules run in
a second process, so every rule that leaks into a controller this week gets
written again there, and the first drift between the copies is a customer whose
order this service accepted and the executor then refused.

## What you deliver

| Deliverable | Where |
|---|---|
| Six endpoints implementing `contracts/trade-api.yaml` | `src/main/java/` |
| A layered controller, service and mapper structure | one package per layer |
| MyBatis mappers with parameterised statements | XML or interface annotations |
| One `@ControllerAdvice` producing the error envelope | as above |
| JWT verification on every `/api/v1/**` route | as above |
| Tests, unit and slice, that run without a container | `src/test/java/` |
| A multi-stage `Dockerfile` | this folder |
| Your service added to the root `docker-compose.yml` | repository root |
| The manifest naming your design for the harness | `manifest.env` |

No starter code and no stubs ship. Deciding what belongs in which layer is most
of what this sprint assesses.

## The engineering contract

No project skeleton ships either. Set one up. Six things about it are fixed,
because the harness, the compose stack and your teammates all depend on them:

- One Maven project rooted in this folder, on Maven 3.9 or later and Java 21.
  `mvn clean verify` succeeds in it on a machine that has never seen your code.
- Spring Boot 3.5.x with the web and validation starters, MyBatis through the
  Spring Boot starter, and the Postgres JDBC driver.
- Your Sprint 5 module as a dependency, by the coordinates you gave it there and
  declared again in the `DOMAIN_*` keys of `manifest.env`. There is no aggregator
  build, so `mvn install` in `sprint-05-domain-engine` runs before `mvn verify`
  here, and again every time the domain changes.
- Sources under `src/main/java`, tests under `src/test/java`, below one base
  package you declare, with controllers in one sub-package and mappers in
  another. Both are declared too: the layering checks find them by name.
- A multi-stage `Dockerfile` of your own design, in this folder.
- The service joined to the root `docker-compose.yml` under the `platform`
  profile, so that `docker compose up -d` stays the infrastructure command.

Three boundaries inside that, stated as the harness reads them. Controller
sources import nothing from your mapper package, `java.sql`, `javax.sql`,
MyBatis, Spring JDBC or a persistence API, and hold no SQL string. The Sprint 5
artefact on the compile classpath references no servlet, Spring or MyBatis type,
read from your local Maven repository, so the boundary holds against what you
published. `JWT_SECRET` comes from the environment at runtime and appears in no
properties file, no YAML file and no Java constant, as does every other value
that differs between a laptop and a container.

```bash
cd sprint-05-domain-engine && mvn install   # publish the domain module first

cd sprint-06-trade-api
mvn clean verify
scripts/check.sh                            # and --live once your stack is up
```

## The contract is the specification

`contracts/trade-api.yaml` is not documentation of something you build. It is
the thing you build, and you neither author it nor change it. It exists so that
the Angular application in Sprint 9 can generate a typed client without reading
your Java. Six operations, with paths, verbs and status codes fixed.

Two parts of it are behaviour rather than decoration, and both are assessed.

**The error envelope.** Every failure leaves as
`{"errorCode": "...", "message": "..."}` and nothing else: no whitelabel page,
no stack trace, no bare status with an empty body. The Angular application has
one error handler because there is one envelope.

**Every code in the catalogue.** Clients branch on `errorCode`, never on the
status alone, because 404 and 409 each carry more than one code.

| Code | HTTP | Raised when |
|---|---|---|
| `ACC-404` | 404 | No account exists with that key |
| `ACC-403` | 403 | The account is not `ACTIVE`, or the token does not reach it |
| `INS-404` | 404 | The instrument is unknown or no longer tradable |
| `ORD-400` | 400 | A buy costs more than the available cash |
| `ORD-409` | 409 | Insufficient holdings, a reused idempotency key, or an order that cannot be cancelled |
| `VAL-422` | 422 | The request failed field validation |
| `AUTH-401` | 401 | Missing, malformed, expired or wrongly signed token |

`message` is for a human reading a screen: no class name, no SQL fragment, no
account key, no internal identifier. What an investigation needs is logged on
the server. Response bodies are the contract schemas, field for field, and
`AccountResponse.accountId` is the one place in the platform where that name
means the string business reference rather than the numeric key.

## Layering, stated concretely

Three layers, and each one is allowed to speak exactly one language.

| Layer | Speaks | Must not |
|---|---|---|
| Controller | HTTP, DTOs, status codes, validation annotations | Contain SQL, open a transaction, or hold a business rule |
| Service | The domain module, mappers, one transaction | Take a servlet type, a request object or a status code as a parameter |
| Mapper | SQL, parameterised, and result mapping | Decide anything, or reach back into HTTP |

Two violations fail review on sight.

**SQL in a controller.** A query in the class that handles the request cannot be
tested without a web layer, cannot be reused by the service needing the same
rows next sprint, and puts your schema and your JSON in one file.

**An HTTP type in the domain.** A domain exception carrying an HTTP status, an
entity annotated for a web framework, or a rule taking a request DTO has bound
the rules to one caller. The Trade Executor in Sprint 7 has no HTTP request and
needs the same rules unchanged.

## MyBatis, and why interpolation is a security finding

Persistence is MyBatis, in XML under `src/main/resources/mapper/` or in
annotations on the mapper interface. Either style is acceptable.

Bind every value arriving from outside with `#{}`, which becomes a JDBC bind
parameter: the driver sends the statement and the value separately, so nothing
the caller sends changes what the statement does. `${}` substitutes the value in
first. A symbol of `AAPL' OR '1'='1` written with `${}` becomes part of the
statement, and the positions that come back are whichever account the attacker
asked for. That is OWASP A03, injection, and the outside values here include an
account key, a symbol, a status filter and two timestamps.

The harness fails the build on any `${}` in a mapper. One use is legitimate, a
column name or sort direction that cannot be a bind parameter, and only when the
value is checked against a fixed list of permitted names first. Declare it in
`MAPPER_SQL_INTERPOLATION_ALLOWLIST` in `manifest.env`, with a comment saying
what does that checking. An entry there is a question the review asks.

## Optimistic locking on the account version column

Sprint 3 put a version column on the account row and Sprint 5 had the domain
report the version it was loaded at. This is the sprint where it does something.

Account 3 holds 25,000, and two buys costing 20,000 each arrive at the same
moment. Without a lock, both read the row, both see 25,000, and both write 5,000
back. Both orders are recorded and filled, 40,000 of stock has been bought, and
the account holds 5,000 instead of being 15,000 overdrawn. One update was lost,
with no error and no symptom until somebody reconciles the cash against the
order history, which in a real firm happens the next morning.

Optimistic locking makes the version part of the write rather than a check
before it. The update names the version the row held when it was read, and
increments it. The database serialises the two writes: the first affects one
row, the second affects none. Zero rows affected is not success, so the service
that gets it refuses the order and the caller sees `ORD-409`. Read the version
with the row, and return the affected row count, because a mapper returning
`void` has thrown away the only evidence that anything happened. The same
applies behind `DELETE /api/v1/orders/{id}`: make the transition conditional on
the state you expect, in one statement.

## The auth stub

`services/auth-stub` is provided. It is a fixture, not a deliverable: nothing in
it is assessed and nothing in it is to be modified. It exists because Sprint 6
has to verify a real token and Node is not taught until Sprint 8. It starts with
the infrastructure on `docker compose up -d`, and `services/auth-stub/README.md`
lists the five demo users, the claims and the shared signing secret.

Verification means checking the signature, the expiry and the algorithm the
token asks for, in that order, before reading a claim. A verifier that decodes
the payload first has already trusted whatever the client sent. A missing
header, a wrong scheme, an expired token and a forged signature are one answer,
`AUTH-401` with the same body, because a more specific message tells an attacker
which of the four they got wrong. Whether the caller holds a valid token is
answered once, for every route under `/api/v1/`, before any controller runs.
Whether that caller may reach the account is answered where the account key is
known, and the answer is `ACC-403` with the same message a suspended account
gets, so that nobody can enumerate keys.

Sprint 8 replaces the stub with the real service. The claims, the algorithm and
the secret are identical by design, so the swap is a configuration change and no
code here is expected to move. If yours needs a code change, something is
coupled to the stub rather than to the token, and that is worth finding now
rather than in week 7.

## The Dockerfile and the compose entry

A single-stage build ships the image that built the service: Maven, a full JDK,
the dependency cache and your source. The reason to care is not disk. Every tool
in an image is a tool available to whoever gets into the container. So one stage
carrying Maven and a JDK 21 builds the jar, and a second carrying a Java runtime
and neither of the other two takes it through `COPY --from=`. Order the copies
so that changing a source file does not invalidate the resolved-dependency
layer, run as a user that is not root, expose the service port and answer a
health check. One constraint decides the build stage: the image build starts
with an empty `~/.m2` and cannot reach the Sprint 5 module on your laptop, so it
builds both projects, both folders sit inside the build context, and Docker
cannot copy from above its context.

Adding the service to `docker-compose.yml` is your change. A correct entry:

| Needs | Because |
|---|---|
| A `build` block with the context and the Dockerfile path | The image is built from source, not pulled |
| `profiles: [platform]` | It starts with `--profile platform`, alongside the other services you write, not with the bare infrastructure |
| `networks: [trading-net]` | It resolves `postgres` and `auth-stub` by service name |
| A published port for the service port | `curl` from the host reaches it |
| Database host, port, name, user and password from the environment | `localhost` inside a container is the container |
| `JWT_SECRET` passed through from `.env` | It has to be the secret the stub signed with |
| `depends_on` Postgres, on its health condition | Starting before the database is ready is a crash loop, not a failure |
| A health check | `docker compose ps` should say the service is up, not merely running |

Nothing this sprint needs Kafka.

## Working with Copilot

GitHub Copilot is introduced this sprint. It is quick at the parts of this
service that look the same in every Spring Boot application, and it knows
nothing about your schema, your Sprint 5 module or the contract unless you open
those files beside the one you are writing. What it produces is assessed exactly
as anything you typed: against the error catalogue, the layering rules and the
parameterisation scan. A generated mapper interpolating a symbol with `${}`
fails the harness under your name. Read each suggestion, and be able to say why
the line is there.

## Acceptance criteria

These are the criteria your instructor assesses against.

1. All six endpoints are implemented and match the contract, including the error
   envelope and every code in the catalogue.
2. Layering is enforced: no SQL in a controller, no HTTP type in the domain.
3. MyBatis mappers use parameterised statements throughout.
4. `@ControllerAdvice` maps every domain exception to its documented code and
   status.
5. Order placement is `@Transactional`.
6. Optimistic locking is applied on the account version column.
7. A protected route rejects a missing or invalid token with `AUTH-401`.
8. The service builds and runs from a multi-stage Dockerfile.

## The check harness

`scripts/check.sh` asserts the things a machine can assert, in two modes.
**Static mode** is the default: no container, no database, no running service
and no call to the Fauxnance API, so run it as often as you like.

| Check | What it proves |
|---|---|
| `mvn clean verify` succeeds from a clean state | The engineering contract, and that the tests pass from the repository |
| Your Sprint 5 artefact resolves from your local Maven repository | Criterion 2, the dependency half |
| No servlet, Spring or MyBatis type in that artefact's classes | Criterion 2, the domain half |
| No `${}` in any mapper statement, XML or annotation | Criterion 3 |
| The order placement path carries `@Transactional` | Criterion 5 |
| A `@ControllerAdvice` or equivalent exists | Criterion 4, the existence half |
| Controller sources import no mapper, JDBC or MyBatis type, and hold no SQL | Criterion 2, the controller half |
| `Dockerfile` has more than one stage, and its final stage is not a build image | Criterion 8 |
| The account version column appears in a mapper that updates | Criterion 6, the static half |

**Live mode** adds the endpoint probes. It needs your stack up: your schema and
seed data applied, the auth stub running, and your service reachable.

```bash
docker compose --profile platform up -d --build
scripts/check.sh --live
```

| Probe | What it proves |
|---|---|
| A token is obtained from the auth stub and accepted | Criterion 7, the positive half |
| A missing token and a tampered token on a protected route | Criterion 7: both `AUTH-401`, both in the envelope |
| All six endpoints answer with the status and body shape the contract states | Criterion 1 |
| An unknown account, an unknown instrument, an inactive account, an unaffordable buy, a reused idempotency key and an invalid field | Criterion 1, the catalogue half |
| Several concurrent orders against one account, reconciled against the cash | Criterion 6, behaviourally: a lost update shows up as cash that did not move |

Both modes read your names from `manifest.env`, so the harness asserts your
design rather than dictating one. Live mode assumes nothing about your schema:
it goes through your API, and needs only the demo user whose token reaches an
active account, the one whose account you seeded inactive, and a symbol you
seeded as tradable.

### What passing does not mean

The harness reads structure, not meaning. It confirms that a mapper binds its
parameters without knowing whether the statement is right, and that an
annotation is present without knowing whether the boundary is where it should
be. Assessed by a human at the review, and not by this script:

- whether the transaction encloses the work that has to be atomic, and no more
- whether every domain exception leaves as its documented code, rather than most
- whether the layering holds where a grep cannot see it, including a business
  rule written in a service that should have called the domain
- whether the lock is applied to every write to the account row
- whether the image would survive being deployed, including what it runs as

Bring to the review: the running stack, one order traced from the request to the
committed row, your Dockerfile, and your answer to what happens when two
customers spend the same money at the same moment.

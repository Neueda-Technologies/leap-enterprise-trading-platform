# Enterprise Trading Platform

A trading platform has to do three things an ordinary CRUD application does
not. It has to record an intention to trade before that trade has happened,
because execution is asynchronous and can fail. It has to keep an audit trail
that survives every restart and every bad deployment, because the record is
the legal position. It has to separate the store that answers "what is my
balance right now" from the store that answers "what did the desk trade last
quarter", because those two questions have incompatible access patterns.

Almost every design decision you will make over the next twelve weeks follows
from one of those three. This repository is your team's copy of the platform.

## What you will have built

By the end of week 12 the platform runs on your machine as a set of containers
and its front end runs on AWS.

A customer signs in through an Angular application, places an order, and
watches it appear in a blotter. Behind that, a Spring Boot service validates
the order against the trading rules, writes it to Postgres and publishes it to
Kafka. A separate executor consumes the order, prices it against a live quote,
decides whether to fill or reject it, and writes the fill, the cash movement
and the position change in one transaction. A poller keeps quotes flowing onto
the bus. A Python pipeline loads a star schema that answers the questions the
transactional database is the wrong shape for. A NestJS service issues and
verifies the tokens holding all of it together. One extension service adds a
capability your team chose. The Angular build is served from a private S3
bucket behind CloudFront.

You build all of it. What you are given is already in this repository: the
contracts your services have to satisfy, the shared infrastructure, and one
authentication fixture that exists so Sprint 6 can verify a real token before
Node is taught.

## The twelve weeks

Sprints 1 and 2 carry no capstone deliverable. They cover environment setup,
Git, agile practice, OWASP and Secure Code Warrior, and nothing in this
repository depends on them. The capstone starts in week 4 and runs to the end.

| Week | Sprint | Taught focus | Capstone deliverable | Folder |
|---|---|---|---|---|
| 1 | Induction | Onboarding and orientation | none | none |
| 2 to 3 | 1 and 2 | Environment, Git, agile practice, OWASP and Secure Code Warrior | none | none |
| 4 | 3 | Data systems and data modelling | The transactional Postgres schema, with constraints, indexes, an ER diagram and seed data | `sprint-03-trade-database` |
| 5 | 4 | Financial services and data analytics | A Python dashboard with three business insights, and ingestion as a tested extract, transform, load pipeline | `sprint-04-analytics-etl` |
| 6 | 5 | Software engineering essentials, Java and OOAD | The trading domain engine in Java 21: entities, enumerations, validated DTOs, an exception hierarchy and the buy and sell rules | `sprint-05-domain-engine` |
| 7 | 6 | Software architecture and enterprise Java | The Trade REST API: a layered, Dockerised Spring Boot service on MyBatis, implementing `contracts/trade-api.yaml` | `sprint-06-trade-api` |
| 8 | 7 | Enterprise data and engineering excellence | Kafka topics, the Trade Executor, the market-data poller and the batch pipeline into the analytical store | `sprint-07-event-backbone` |
| 9 | 8 | Node.js, NestJS and authentication | The NestJS auth service implementing `contracts/auth-api.yaml`, replacing the stub | `sprint-08-auth-service` |
| 10 | 9 | UI development with Angular | The Angular application: login, dashboard, order ticket and blotter, with unit and Playwright tests | `sprint-09-trading-ui` |
| 11 | 10 | Applied project week | One extension microservice from the catalogue, integrated end to end, with a decision log | `sprint-10-extension-service` |
| 12 | 11 | Cloud, deployment and final showcase | The Angular build on S3 behind CloudFront, deployed by one automated cycle, then the showcase | `sprint-11-cloud-deploy` |

## Sprint folders

One folder per sprint, `sprint-03-trade-database` through
`sprint-11-cloud-deploy`. Each holds its own README: why the component exists,
what you have to deliver, and the criteria you are assessed against. Read that
README on the Monday, not on the Thursday.

The folders are ordered but they are not separate exercises. The platform
accumulates. The schema you design in Sprint 3 is the schema the Trade REST
API writes to in Sprint 6 and the schema the pipeline reads in Sprint 7. A
weak decision in week 4 is a fortnight of friction in week 8. Nothing is
thrown away at the end of a sprint, and no sprint is finished until the
sprints before it still work.

## Repository layout

```
contracts/            Binding API and message contracts. Start here each sprint.
infra/                Shared infrastructure: Postgres and Kafka, and how to run them.
services/             Platform services. auth-stub is provided; the rest are yours.
sprint-NN-<slug>/     One folder per sprint, brief and acceptance criteria inside.
docker-compose.yml    The local stack. Add your services to it as you build them.
.env.example          Template for .env. Copy it, never commit the copy.
```

## Running the shared infrastructure

Docker is the only hard prerequisite for the first sprint. You will also need
a JDK 21, Node 20 or later, and Python 3.12 or later before Sprints 5, 8 and 4
respectively.

```bash
cp .env.example .env
docker compose up -d
```

That starts Postgres and Kafka and creates the topics named in
`contracts/kafka-topics.md`. Postgres comes up empty, because the schema is
yours to design in Sprint 3. From Sprint 6, add the provided auth stub:

```bash
docker compose --profile platform up -d --build
```

Check it:

```bash
docker compose ps
docker compose exec postgres psql -U postgres -d trading -c '\dt'
```

`infra/README.md` covers connection details, resetting the data, adding your
own services to the stack, and what to do when a container will not start.

## Market data

Prices come from the Fauxnance API, a hosted service that serves end-of-day
candles and delayed quotes for US and Indian equities, foreign exchange and
crypto. Swagger UI is at `/v1/docs` on the base URL in `.env.example`.

Your instructor issues you a personal key. Send it in the `X-Api-Key` header.
The quota is 2000 requests per day per key.

| Endpoint | Use |
|---|---|
| `GET /candles/{symbol}` | Historical end-of-day open, high, low, close and volume. Sprint 4 analytics. |
| `GET /quotes/{symbol}` | One delayed quote. The Trade Executor prices a fill with this. |
| `GET /quotes?symbols=A,B,C` | Batch quotes, up to 25 symbols, counting as one request against the quota. |
| `GET /usage` | Your own quota status. Check it before assuming the service is broken. |
| `GET /health` | No key required. Use it to rule out the API before debugging your client. |

Four rules, and none of them is negotiable.

The key is read from the environment, from `FAUXNANCE_API_KEY`. It is never a
literal in source, never in a properties file, never in a test fixture. `.env`
is git-ignored for that reason. A key that reaches a commit has to be revoked,
and the history keeps it whether or not you revoke it.

The Angular application never calls Fauxnance. Doing so ships your key to
every browser that loads the page. Prices reach the browser through one of
your own services.

There is no price stream. Fauxnance has no WebSocket and no server-sent
events. The stream that Sprint 10 extensions consume is one you create in
Sprint 7, by polling the batch quotes endpoint and publishing each quote to
the `market-data` topic.

2000 requests a day is not generous, and it is meant not to be. A team polling
every symbol every second exhausts a key before lunch. Poll only the symbols
you hold or watch, batch up to 25 in one call, and cache what does not change
between calls.

## Working as a team

You are assessed as a team on a platform, and individually on your ability to
explain it. Both of those shape how you should work.

Split the build, but rotate the split. A team where one person owns Java for
twelve weeks produces one competent Java developer and three people who cannot
answer a question about half the system at the showcase. Every member is
expected to walk any component unaided, including the parts they did not
write.

Work on branches and review each other's pull requests. Keep the main branch
in a state where a teammate can clone it, run `docker compose up -d`, and get
a working stack. Commit in small pieces with messages that say why, because
Sprint 7 asks you to write characterisation tests around existing code and a
history of one commit per week tells you nothing about how that code came to
be.

Write decisions down as you take them. The Sprint 10 deliverable includes a
decision log, and a log assembled from memory in the final week is a work of
fiction. When you choose a partition count, a fill rule or an index, record
what you chose and what you rejected.

Treat secrets as a hard rule rather than a preference. No key, password or
token in the repository, at any point, in any branch. A secret in a commit is
still in the history after you delete it.

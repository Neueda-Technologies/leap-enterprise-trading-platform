# Contracts

A contract is the part of your system that other people depend on. The Angular
application generates its client from the OpenAPI files here, so a field you
rename in a controller is a compile error in the UI. A consumer deserialises
the message envelope described here, so a producer that drops a field breaks a
service somebody else wrote. Everything in this directory is binding: build to
it rather than around it.

Read the contract for a sprint before you write any code for that sprint. Each
file carries a long description at the top explaining the reasoning behind the
shape it specifies, not only the shape itself.

## What is here

| File | What it specifies | First used |
|---|---|---|
| `trade-api.yaml` | OpenAPI 3.1 for the Trade REST API: order placement and cancellation, account details, balance, positions and order history, the error envelope and the full error-code catalogue. | Sprint 6 |
| `auth-api.yaml` | OpenAPI 3.1 for authentication: registration, login, refresh and current user, and the exact JWT claims. It describes two interchangeable implementations, the stub you are given and the service you build. | Sprint 6, against the stub. Implemented in Sprint 8. |
| `kafka-topics.md` | The topic catalogue: names, message keys, partition counts, retention, the shared event envelope, the payload schema for every event type, and which service produces and consumes each topic. | Sprint 7 |
| `analytics-schema.sql` | The star schema for the analytical store: one fact table and its dimensions, in ANSI SQL that runs on Snowflake, DuckDB or SQLite. | Sprint 4, read. Loaded by the pipeline in Sprint 7. |
| `portfolio-api.yaml` | OpenAPI 3.1 for the Portfolio and P&L service: priced holdings, cost basis, and realised and unrealised profit and loss. | Sprint 10, and only if your team chooses that extension. |

## What is not here

There is no schema for the transactional database. You design that in Sprint 3
from the domain, and the design decisions involved are most of the point of
the sprint. The analytical schema is given because it is a modelling style you
have not met yet and because two teams inventing incompatible fact tables
would make the Sprint 7 pipeline work unassessable.

## Working with them

Generate clients rather than hand-writing them. The Angular acceptance
criteria require it, and a generated client fails at build time when a
contract moves, which is the failure you want.

Serve the OpenAPI files from the running service as well. A contract that only
exists in a repository drifts from the service within a fortnight.

If you believe a contract is wrong, raise it with your instructor. Do not
change it locally and carry on. Another team's service is reading the same
file, and a private fix becomes an integration failure at the showcase.

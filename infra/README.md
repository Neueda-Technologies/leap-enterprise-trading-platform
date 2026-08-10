# Infrastructure

The shared local stack: one Postgres instance, one Kafka broker, a one-shot
topic creator, and the provided auth stub. Everything here is wired by the
root `docker-compose.yml`. Nothing here is a deliverable, and nothing here is
assessed. It exists so that Sprint 3 has a database on day one and Sprint 7
has a broker on day one.

Postgres ships empty. There is no schema and no seed data on this branch,
because designing the schema is the Sprint 3 deliverable and being handed one
would remove the exercise.

## Before the first run

```bash
cp .env.example .env
```

Edit `.env` and replace `FAUXNANCE_API_KEY` with the key issued to you. Every
other value has a working local default. `.env` is git-ignored and must stay
that way.

## Start and stop

```bash
docker compose up -d          # start everything in this file
docker compose ps             # what is running and whether it is healthy
docker compose logs -f kafka  # follow one container's logs
docker compose stop           # stop the containers, keep the data
docker compose down           # stop and remove the containers, keep the data
```

Start a subset by naming it. Sprints 3 to 5 need only the database:

```bash
docker compose up -d postgres
```

`kafka-init` runs to completion and exits, so `docker compose ps` showing it
as exited is the expected state, not a failure. Check its log if a topic is
missing.

## What runs where

| Container | Purpose | Port |
|---|---|---|
| `postgres` | PostgreSQL 16, empty on first start | 5432 |
| `kafka` | Kafka 3.8 broker in KRaft mode, single node | 9092 from your machine, 29092 inside the compose network |
| `kafka-init` | Creates the topics, then exits | none |
| `auth-stub` | Provided JWT issuer, Sprints 6 and 7 | 3001 |

Port 3000 is deliberately unused. The auth service you build in Sprint 8
listens there, per `contracts/auth-api.yaml`, so both can run side by side
during the cutover.

## Connecting

Postgres from your machine, with `psql` or any client:

```bash
psql -h localhost -p 5432 -U postgres -d trading
```

Postgres from inside a container on `trading-net`, which is what a JDBC URL in
your Spring Boot service uses:

```
jdbc:postgresql://postgres:5432/trading
```

A shell inside the container, no local client needed:

```bash
docker compose exec postgres psql -U postgres -d trading
```

Kafka has two addresses and using the wrong one is the most common first-day
problem. A tool on your machine uses `localhost:9092`. A service running as a
compose container uses `kafka:29092`. Both reach the same broker.

List the topics:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list
```

Describe one to confirm its partition count:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --describe --topic market-data
```

Read a topic from the beginning, which is the quickest way to prove a producer
works before a consumer exists:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic trade-events --from-beginning
```

## Topics

`infra/kafka/create-topics.sh` creates the three topics in
`contracts/kafka-topics.md`, with the partition counts and retention that
contract specifies, plus a dead-letter topic for each. Auto-creation is off on
the broker, because an auto-created topic gets one partition and default
retention, which is wrong for all three.

The script is idempotent. Rerun it after editing it, or after a reset:

```bash
docker compose run --rm kafka-init
```

Read the script before Sprint 7 rather than treating it as magic. The
partition counts in it are decisions with consequences, and the contract
explains each one. You are expected to be able to justify them.

## Loading your schema

Anything you put in `infra/postgres` ending in `.sql` or `.sh` runs once, in
filename order, the first time the container starts against an empty data
volume. Numbering the files keeps that order explicit, for example
`01-schema.sql` then `02-seed.sql`. This is a convenience for local work, not
a migration tool: decide in Sprint 3 how your team versions schema changes and
say so in your design notes.

The scripts do not rerun against a volume that already has data. Reset the
volume to apply them again.

## Resetting

Drop everything, including all database data and every message on every topic:

```bash
docker compose down -v
docker compose up -d
```

Reset Postgres only and leave Kafka's data alone:

```bash
docker compose down
docker volume rm india_postgres-data
docker compose up -d
```

The volume name is prefixed with the Compose project name, which defaults to
the name of the directory you cloned into. Run `docker volume ls` to confirm
it if you renamed the directory.

## When something will not start

Work through these in order before asking for help, and bring the output with
you.

| Symptom | Check |
|---|---|
| `port is already allocated` | Another Postgres or Kafka is running locally. `lsof -i :5432` and stop it, or change the published port. |
| `auth-stub` exits immediately | `JWT_SECRET` is unset. The stub refuses to start without one. Confirm `.env` exists. |
| Topics missing | `docker compose logs kafka-init`. The broker may not have become healthy inside the wait. |
| A service cannot reach the database | It is using `localhost` from inside a container. Inside the compose network the host is `postgres`. |
| Init scripts did not run | The volume was not empty. `docker compose down -v` and start again. |

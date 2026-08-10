# Infrastructure

Postgres and Kafka run in Docker for the whole of the capstone. Nothing you
build talks to a database or a broker installed on your own machine, so that
every member of the team is running the same versions and a problem on one
laptop is reproducible on another. This file covers `infra/` and the root
`docker-compose.yml`. Instructions for building or testing an individual
service live with that service.

## Before the first run

```bash
cp .env.example .env
```

Edit `.env` and replace `FAUXNANCE_API_KEY` with the key your instructor
issued you. Every other value has a working development default. `.env` is
git-ignored; `.env.example` is the committed template.

## What runs where

| Service | Compose name | Port | Started by |
|---|---|---|---|
| PostgreSQL 16 | `postgres` | 5432 | default, no profile |
| Kafka 3.8, KRaft mode, single broker | `kafka` | 9092 from the host, 29092 inside the compose network | default, no profile |
| Topic creation, one-shot | `kafka-init` | none | default, no profile |
| Auth stub, provided | `auth-stub` | 3001 | `--profile platform` |

## Starting and stopping

Infrastructure only. This is what Sprints 3 to 5 need:

```bash
docker compose up -d
```

Infrastructure plus the provided auth stub, which you need from Sprint 6:

```bash
docker compose --profile platform up -d --build
```

Stop everything and keep the data:

```bash
docker compose down
```

Follow the logs of one container:

```bash
docker compose logs -f kafka
```

Add the services you build to `docker-compose.yml` under the `platform`
profile as you write them. Compose does not require every service in a profile
to start together, so you can bring up one of them against the
infrastructure while the others are still half-written:

```bash
docker compose --profile platform up -d --build trade-api
```

## Connecting

| Target | From the host | From another compose service |
|---|---|---|
| Postgres | `localhost:5432` | `postgres:5432` |
| Kafka | `localhost:9092` | `kafka:29092` |
| Auth stub | `http://localhost:3001` | `http://auth-stub:3001` |

The database name, user and password are whatever you set in `.env`, and
default to `trading`, `postgres` and `postgres_dev_password`. A psql session
inside the container:

```bash
docker compose exec postgres psql -U postgres -d trading
```

The two Kafka addresses are not interchangeable. A service running inside
compose that is pointed at `localhost:9092` is looking for a broker inside its
own container and will fail to connect. Read `KAFKA_BOOTSTRAP_SERVERS` from
the environment rather than hard-coding either value.

## Topics

`kafka-init` creates the topics in `contracts/kafka-topics.md` and then exits.
Partition counts and retention come from that contract, and the script is
idempotent, so a topic that already exists is left alone. List what exists:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list
```

Expect `orders`, `trade-events`, `market-data` and a `.DLT` dead-letter topic
for each. Check the partition count and retention of one topic:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --describe --topic market-data
```

Rerun topic creation after editing `infra/kafka/create-topics.sh`:

```bash
docker compose run --rm kafka-init
```

Produce and consume by hand, which is the quickest way to tell a broken
producer from a broken consumer:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic market-data --from-beginning
```

## Resetting

The Postgres init scripts in `infra/postgres/` run only on the first start
against an empty volume. Changing them does nothing until the volume is gone.
To reload your schema and seed data from scratch:

```bash
docker compose down -v
docker compose up -d
```

`-v` removes the named volumes, so this also clears every topic and every
message on the broker. That is usually what you want during a sprint. To reset
Postgres and leave Kafka alone, remove the one volume by name:

```bash
docker compose down
docker volume rm us-ireland_postgres-data
docker compose up -d
```

The volume name is prefixed with the Compose project name, which defaults to
the name of the directory you cloned into. Run `docker volume ls` to confirm
it.

Get into the habit of resetting often. A schema that only works because of
something you did by hand three days ago is a schema that will not survive the
showcase.

## When it will not start

| Symptom | Usual cause |
|---|---|
| `bind: address already in use` on 5432 | A Postgres installed on the host is holding the port. Stop it, or change the published port in `docker-compose.yml`. |
| `kafka-init` exits non-zero on first run | The broker was not ready. `docker compose up -d` again; the script waits and is safe to rerun. |
| Init scripts did not run | The volume already existed. `docker compose down -v` and start again. |
| A service cannot reach the broker | It is pointed at `localhost:9092` from inside compose. Use `kafka:29092`. |

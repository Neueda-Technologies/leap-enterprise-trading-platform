# Infrastructure

What runs where, how to start a partial stack for one sprint's work, and how
to check that it is working. This file covers `infra/` and the root
`docker-compose.yml`. It does not cover any one service's own build or test
instructions; those live with the service.

## Before the first run

Copy the environment template and fill in your own Fauxnance key:

```bash
cp .env.example .env
```

Edit `.env` and replace `FAUXNANCE_API_KEY`. Every other value in the
template has a working development default and does not need to change to
run the stack locally. See the root `.env.example` for what each variable
does.

## What runs where

| Service | Compose name | Port | Started by |
|---|---|---|---|
| PostgreSQL 16 | `postgres` | 5432 | default, no profile |
| Kafka, KRaft mode, single broker | `kafka` | 9092 external, 29092 inside the compose network | default, no profile |
| Topic creation, one-shot | `kafka-init` | none | default, no profile |
| Trade REST API | `trade-api` | 8080 | `--profile platform` |
| Auth service | `auth-service` | 3000 | `--profile platform` |
| Auth stub | `auth-stub` | 3001 | `--profile platform` |
| Trade Executor | `trade-executor` | 8082 | `--profile platform` |
| Market-data poller | `market-data-poller` | 8083 | `--profile platform` |
| Portfolio and P&L | `portfolio-service` | 8081 | `--profile platform` |

`docker compose up` on its own starts only the first three rows. That
matches the order the platform is built in: Sprint 3 needs a database before
any service exists, and Sprint 7 needs a broker before the executor and the
poller are written. Run the infrastructure profile on its own for that work:

```bash
docker compose up -d
```

Bring up the full platform once the services exist:

```bash
docker compose --profile platform up -d --build
```

### Running one service against the infrastructure

Compose does not require every service in a profile to start together. To
run only the Trade REST API against the infrastructure, for example while
building Sprint 6 and before the executor exists:

```bash
docker compose up -d
docker compose --profile platform up -d --build trade-api
```

### Auth service and auth stub

Both are defined under `--profile platform` and both can run at once,
because they listen on different host ports (3000 and 3001) for exactly
that reason. Only one is normally the token issuer that other services are
configured to trust at a given point in the build: the auth stub in
Sprints 6 and 7, the auth service from Sprint 8. Switching which one is
authoritative is a matter of which port a client points at and does not
require rebuilding either container, per `docs/DECISIONS.md`, decision 5.
Stop the one you are not using if running both is confusing during
development:

```bash
docker compose stop auth-stub
```

## Environment variable conventions

Service build contexts under `services/` and `extensions/` are owned by
other parts of this build. Where a service already has code in the
repository, the table below states what it actually reads, checked against
its source. Where a service does not yet exist, the table states the
convention this file wires in as a best guess; confirm it once the service
lands, and raise a mismatch rather than silently duplicating a variable
under two names.

| Variable | Meaning | Wired into | Confirmed against |
|---|---|---|---|
| `DB_URL` | JDBC connection string, for a Java service reading it directly | trade-api, trade-executor, portfolio-service | `extensions/portfolio-pnl/src/main/resources/application.yml` |
| `DB_USERNAME`, `DB_PASSWORD` | Discrete Spring datasource credentials | trade-api, trade-executor, portfolio-service | `extensions/portfolio-pnl/src/main/resources/application.yml`, note the Spring property is `username`, not `user` |
| `DATABASE_URL` | `postgresql://` connection string, preferred over the discrete fields below when both are set | auth-service, trade-executor, portfolio-service | `services/auth-service/src/config/configuration.ts`, `src/database/database.module.ts` |
| `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` | libpq-standard fallback, read only when `DATABASE_URL` is unset | auth-service | `services/auth-service/src/config/configuration.ts` |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` | Best-guess discrete parameters kept for a service that does not follow either convention above | trade-executor | not yet confirmed, `services/trade-executor` had no `application.yml` at time of writing |
| `KAFKA_BOOTSTRAP_SERVERS` | Broker address inside the compose network, `kafka:29092` | trade-api, trade-executor, market-data-poller, portfolio-service | `extensions/portfolio-pnl/src/main/resources/application.yml` |
| `KAFKA_CONSUMER_GROUP` | Explicit consumer group id, per `docs/contracts/kafka-topics.md`'s producer and consumer matrix | trade-executor (`trade-executor`), portfolio-service (`portfolio-service`) | not yet confirmed for trade-executor; portfolio-pnl hard-codes its group id rather than reading it from the environment, so this variable is currently unused there |
| `FAUXNANCE_BASE_URL`, `FAUXNANCE_API_KEY` | Passed through from `.env`, never generated by compose | trade-executor, market-data-poller, portfolio-service | `extensions/portfolio-pnl/src/main/resources/application.yml` |
| `JWT_SECRET` | Shared HS256 signing secret. Must be at least 32 characters: the auth service refuses to start on a shorter one | trade-api, auth-service, auth-stub, portfolio-service | `services/auth-service/src/config/configuration.ts`, `extensions/portfolio-pnl/.../JwtService.java` |
| `TRADE_API_BASE_URL` | Where the Portfolio and P&L service reads cash balance from | portfolio-service | not yet confirmed |

`trade-api` does not hold a Fauxnance key: the architecture keeps
third-party HTTP calls out of the order-write path, so the Trade REST API
never calls Fauxnance itself. `trade-api` and `portfolio-service` do not
call the auth service over the network either; both verify the JWT
signature locally against `JWT_SECRET`, which is why the same secret must
reach every service that checks a token, not only the one that issues it.

Container health checks in `docker-compose.yml` use a plain TCP probe
against each service's port rather than an HTTP call to a `/health`
endpoint. That is deliberate: this file does not control what each
service's Dockerfile installs, and a `curl`- or `wget`-based check would
fail on a minimal base image that has neither. A TCP probe only needs the
process to be listening, which is a weaker guarantee than "the service is
ready" but does not depend on anything beyond `bash`. Tighten the check to
hit the documented health endpoint once a service's own Dockerfile
guarantees a suitable HTTP client is present. `portfolio-service` already
exposes Spring Actuator's `/actuator/health`, per its `application.yml`;
switch its check to that endpoint once its Dockerfile is confirmed to carry
`curl` or `wget`.

## Resetting data

The Postgres init scripts in `infra/postgres/` only run the first time the
`postgres` container starts against an empty volume. To reload the schema
and the seed data from scratch:

```bash
docker compose down -v
docker compose up -d postgres
```

`-v` removes the named volumes, including `kafka-data`, so this also clears
every topic and every message on the broker. To reset only Postgres and
leave Kafka's data alone, remove the one volume by name instead:

```bash
docker compose down
docker volume rm enterprise-trading-platform_postgres-data
docker compose up -d postgres
```

The exact volume name is prefixed with the Compose project name, which
defaults to the directory name. Run `docker volume ls` to confirm it if
you have renamed the checkout directory.

## Verifying the stack

### Postgres

```bash
docker compose exec postgres psql -U postgres -d trading -c "SELECT id, account_id, holder_name, status FROM accounts ORDER BY id;"
```

Expect five rows: accounts 1 to 3 `ACTIVE`, account 4 `SUSPENDED`, account 5
`CLOSED`. Confirm the seeded order spread:

```bash
docker compose exec postgres psql -U postgres -d trading -c "SELECT status, count(*) FROM orders GROUP BY status ORDER BY status;"
```

Expect all four statuses represented: `NEW`, `FILLED`, `REJECTED`,
`CANCELLED`. Confirm positions reconcile against the seeded fills:

```bash
docker compose exec postgres psql -U postgres -d trading -c "SELECT * FROM positions ORDER BY account_id, symbol;"
```

### Kafka

List the topics the init container created:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

Expect `orders`, `trade-events`, `market-data` and their three `.DLT`
counterparts. Kafka logs a warning when creating a topic whose name mixes a
period and would-be underscore forms, because of a metric-naming
limitation; the warning is expected for the `.DLT` topics and is not an
error, since none of these topic names also uses an underscore.

Describe a topic to check its partition count and retention:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic market-data
```

Produce a test message and read it back:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 --topic market-data --property "parse.key=true" --property "key.separator=:"
# type: AAPL:{"eventId":"test","eventType":"QUOTE","eventTime":"2026-08-06T00:00:00Z","source":"manual-test","schemaVersion":1,"payload":{"symbol":"AAPL","price":230.00,"currency":"USD","stale":false,"quoteAsOf":"2026-08-06T00:00:00Z"}}
# then Ctrl-D
```

```bash
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic market-data --from-beginning --max-messages 1
```

From the host, outside any container, the broker is reachable at
`localhost:9092`, using the same commands with
`--bootstrap-server localhost:9092` if you have a local Kafka client
installed. Tools running inside another compose service use
`kafka:29092`.

### Rerunning topic creation by hand

`kafka-init` exits after it runs once. To rerun it, for example after
changing `infra/kafka/create-topics.sh`:

```bash
docker compose run --rm kafka-init
```

The script is idempotent: creating a topic that already exists with the
same name is a no-op, not an error.

## Ports summary

| Port | Service | Notes |
|---|---|---|
| 5432 | postgres | |
| 9092 | kafka | External, host and out-of-compose tools |
| 29092 | kafka | Internal only, not published to the host |
| 8080 | trade-api | |
| 3000 | auth-service | |
| 3001 | auth-stub | |
| 8082 | trade-executor | Health only, no business endpoint |
| 8083 | market-data-poller | Health only, no business endpoint |
| 8081 | portfolio-service | |

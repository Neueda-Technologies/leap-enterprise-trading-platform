# Auth service

Sprint 8. NestJS 11 on Node 20, TypeScript, argon2, Postgres, Jest. Implements `docs/contracts/auth-api.yaml`.

## Why this service exists

Every other service in the platform needs to know who is calling and which account they may act on, and none of them should hold a password to find out. This service is the only component that ever sees a credential. It verifies one, then hands out a signed statement of identity that any other service can check with a signature and no network call.

It replaces the Sprint 6 auth stub in `services/auth-stub`. The acceptance criterion for the swap is that the Trade REST API and the Angular UI change nothing but configuration. That holds because both implementations sign HS256 with the same `JWT_SECRET` and issue the same claims. `test/contract-parity.spec.ts` proves it and fails the moment the two drift.

## The four routes

| Method | Path | Protected | Success | Failures |
|---|---|---|---|---|
| POST | `/auth/register` | no | 201 `UserResponse` | 409 `AUTH-409`, 422 `VAL-422` |
| POST | `/auth/login` | no | 200 `TokenResponse` | 401 `AUTH-401`, 422 `VAL-422`, 429 `AUTH-429` |
| POST | `/auth/refresh` | no | 200 `TokenResponse` | 401 `AUTH-401`, 422 `VAL-422` |
| GET | `/auth/me` | bearer token | 200 `UserResponse` | 401 `AUTH-401` |

Live OpenAPI at `http://localhost:3000/docs`, generated from the decorators on the controller and the DTOs. The JSON document is at `/docs/json`. Nothing else is exposed: there is no health route, because the contract does not describe one, and the container health check uses `/docs/json` instead.

Registration returns no tokens. An unauthenticated endpoint that mints a session is an authentication bypass waiting for its first defect, so the client logs in afterwards.

## The token contract

Access tokens carry exactly these claims. Adding one is a contract change; renaming one breaks the Trade REST API's authorisation check.

```json
{
  "sub": "3395aba0-5dde-52cf-b7b6-d1d1c91c2086",
  "accountId": 1,
  "roles": ["CUSTOMER"],
  "iat": 1786042773,
  "exp": 1786043673,
  "iss": "auth-service"
}
```

Header: `{"alg":"HS256","typ":"JWT"}`.

| Token | Form | Lifetime | Revocable | Stored |
|---|---|---|---|---|
| Access | Signed JWT | 15 minutes | no | nowhere |
| Refresh | 32 random bytes, hex | 7 days | yes | as a SHA-256, in `auth.refresh_tokens` |

The access token is stateless so that every other service can verify a request without calling back here. The price is that it cannot be withdrawn, and fifteen minutes is the size of that price. The refresh token is the opposite: opaque, single use, stored, and revocable.

Refresh rotates. The presented token is consumed and a new pair is issued. Presenting a consumed token means either a client repeated a request or somebody stole the token, and the service cannot tell which, so it revokes every live token for that user and returns `AUTH-401`.

## Error envelope

`{ "errorCode": ..., "message": ... }` on every failure, and nothing else in the body.

| Code | HTTP | When |
|---|---|---|
| `AUTH-401` | 401 | Unknown username, wrong password, expired token, wrong signature, malformed header, consumed refresh token |
| `AUTH-409` | 409 | Username already taken |
| `VAL-422` | 422 | Field validation failed, including an unknown trading account |
| `AUTH-429` | 429 | Login throttle exceeded |
| `AUTH-500` | 500 | Unhandled server fault |

The first three are in the contract. `AUTH-429` and `AUTH-500` extend the catalogue and are scoped to this service, the same way `AUTH-409` extends the platform catalogue in `trade-api.yaml`. They cover two failures the contract does not describe: throttling, which Sprint 8 requires, and an unhandled fault, which every service has. A client that does not recognise a code falls back to a generic message.

Every authentication failure returns the same body and the same status, whatever the cause. An unknown username also costs the same time as a wrong password, because the unknown-user path verifies a dummy argon2 hash rather than returning early. Matching bodies with mismatched timings is still a username oracle.

## Running it

```bash
cp .env.example .env
npm install
npm run start:dev
```

The service needs Postgres. Point it at the platform database with `DATABASE_URL`, or with `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` and `PGDATABASE`.

```bash
curl -s -X POST http://localhost:3000/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"demo1","password":"Trainee#2026"}'
```

### Configuration

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `3000` | Listen port. The contract fixes 3000 for both implementations. |
| `JWT_SECRET` | none, required | HS256 signing secret, minimum 32 characters. Boot fails without it. |
| `JWT_ISSUER` | `auth-service` | The `iss` claim. |
| `ACCESS_TOKEN_TTL_SECONDS` | `900` | Access token lifetime. |
| `REFRESH_TOKEN_TTL_SECONDS` | `604800` | Refresh token lifetime. |
| `DATABASE_URL` | unset | Full connection string. Overrides the discrete `PG*` variables. |
| `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` | `localhost`, `5432`, `postgres`, `postgres`, `trading` | Connection parts. |
| `AUTH_RUN_MIGRATIONS` | `true` | Apply `migrations/users.sql` at boot. |
| `AUTH_SEED_DEMO_USERS` | `false` | Seed `demo1` to `demo5`. |
| `LOGIN_THROTTLE_LIMIT` | `5` | Login attempts per window, per address. |
| `LOGIN_THROTTLE_TTL_SECONDS` | `60` | The window. |
| `CORS_ORIGINS` | `http://localhost:4200` | Comma-separated browser origins. |

## Schema

`migrations/users.sql` creates the `auth` schema, `auth.users` and `auth.refresh_tokens`. The credential store is owned by this service and by nothing else, which is why its DDL ships here rather than in the shared Sprint 3 init scripts, and why it sits in its own schema: the Trade REST API's application role has no grant on `auth.users`, so an injection defect in the trading path cannot read a password hash.

Two supported ways to apply it:

1. **Service-run, the default.** The service executes the file in one transaction at boot. Every statement is idempotent, so a restart is a no-op. This is the default because the service must come up on a database a participant created by hand, without a second manual step.
2. **Infrastructure-run.** Set `AUTH_RUN_MIGRATIONS=false` and have the platform infrastructure apply it, either by mounting the file into the Postgres container's init directory alongside the Sprint 3 schema, or with `psql -h localhost -U postgres -d trading -f migrations/users.sql`.

Use the second wherever the service connects as a least-privilege role, which is what a production deployment should do: an application role with DDL rights can drop the table it is meant to read.

`auth.users.account_id` references `accounts.id`, the numeric surrogate key, not `accounts.account_id`. The foreign key is added only when the accounts table already exists, so the file applies cleanly to an empty database. Where the constraint is absent, registration still checks the account with a query, and re-running the file after the trading schema appears adds the constraint.

## Demo users

Set `AUTH_SEED_DEMO_USERS=true` and the service seeds five users at boot, idempotently.

| Username | Password | `accountId` | Roles |
|---|---|---|---|
| `demo1` | `Trainee#2026` | 1 | `CUSTOMER` |
| `demo2` | `Trainee#2026` | 2 | `CUSTOMER` |
| `demo3` | `Trainee#2026` | 3 | `CUSTOMER` |
| `demo4` | `Trainee#2026` | 4 | `CUSTOMER` |
| `demo5` | `Trainee#2026` | 5 | `CUSTOMER` |

They map one to one onto the seeded trading accounts, so logging in as `demo3` gives a token that can trade account 3. The stub serves the same five with the same password and the same identifiers: each `sub` is a name-based UUID derived from the username, so both implementations compute it without either one calling the other.

A shared password committed to a repository is acceptable in a training environment and nowhere else. The flag defaults to false for that reason.

## Layout

```
src/
  auth/      controller, service, guard, request and response DTOs
  users/     repository, service, password hashing, demo seeding
  tokens/    signing, verification, refresh-token storage
  database/  connection pool, boot-time schema bootstrap
  common/    error envelope, structured logger, @CurrentUser decorator
  config/    environment loading and validation
migrations/users.sql
test/contract-parity.spec.ts
```

Dependencies run one way: `auth` depends on `users` and `tokens`, both depend on `database`, and nothing depends on `auth`. The controller takes a validated DTO, calls one service method, and maps the result. No SQL in a controller, no HTTP status in a repository.

## Tests

```bash
npm test              # the whole suite
npm run test:parity   # the stub-against-service contract check
npm run test:cov      # with coverage
```

Seven suites, sixty-nine tests, no database and no HTTP server required. The password tests run the real argon2 binding rather than a mock, because the thing under test is that the stored value is a salted argon2id hash, which only the real library can show.

What is covered:

| Suite | Proves |
|---|---|
| `tokens/token.service.spec.ts` | Claims match the contract exactly; HS256; 15-minute expiry; a wrong secret, an expired token, a tampered payload and an `alg: none` token are all rejected; refresh rotation, single use and chain revocation on replay |
| `auth/guards/jwt-auth.guard.spec.ts` | Missing header, wrong scheme, bare token, oversized header; a rejected token attaches no identity; a correctly signed token that does not carry the claims contract is refused |
| `auth/auth.service.spec.ts` | An unknown username and a wrong password produce an identical exception; no token is issued on failure; refresh and current-user failure paths |
| `users/users.service.spec.ts` | Plaintext never reaches the repository; a self-declared `ADMIN` role is dropped; a taken username maps to `AUTH-409`; the unknown-username path still verifies a hash |
| `users/password.service.spec.ts` | argon2id with its parameters and a fresh salt per hash; correct and incorrect passwords; a corrupt stored value fails rather than throws |
| `common/errors/auth-exception.filter.spec.ts` | Every exception leaves as `{errorCode, message}` and nothing else; an internal fault leaks no detail |
| `test/contract-parity.spec.ts` | A stub token verifies here and a token from here verifies in the stub; identical claim names, types, algorithm and lifetime; the same `sub` for each demo user; only `iss` differs |

## Security notes for the Sprint 8 review

| Control | Where |
|---|---|
| argon2id, 19 MiB, two iterations | `users/password.service.ts` |
| No password, token or hash in any log | `common/logging/json.logger.ts` redacts by key at any depth |
| Identical response and comparable timing for unknown user and wrong password | `users/users.service.ts` verifies a dummy hash |
| Refresh rotation, single use, chain revocation on replay | `tokens/token.service.ts`, guarded `UPDATE` in `tokens/refresh-token.repository.ts` |
| Signature, expiry and algorithm checked before any claim is read | `tokens/token.service.ts`, `auth/guards/jwt-auth.guard.ts` |
| `alg` pinned to HS256, so `alg: none` and algorithm confusion are refused | `tokens/token.service.ts` |
| Identity taken from the verified token only | `common/decorators/current-user.decorator.ts` |
| Self-declared roles ignored on public registration | `users/users.service.ts` |
| Unknown request fields rejected | global `ValidationPipe`, `whitelist` and `forbidNonWhitelisted` |
| Parameterised statements throughout | `users/users.repository.ts`, `tokens/refresh-token.repository.ts` |
| Login throttled | `ThrottlerGuard` on `/auth/login` only |
| Secrets from the environment, boot refused on a weak or missing secret | `config/configuration.ts` |
| Container runs as a non-root user with no compiler present | `Dockerfile` |

HS256 means the Trade REST API holds the signing secret in order to verify. RS256 with a published public key removes that, and the contract documents it as an upgrade rather than a requirement. Take it if a team wants verification without shared signing power.

## Docker

```bash
docker build -t auth-service .
docker run --rm -p 3000:3000 \
  -e JWT_SECRET=development-only-shared-secret-change-me \
  -e PGHOST=postgres -e PGDATABASE=trading \
  -e AUTH_SEED_DEMO_USERS=true \
  auth-service
```

Two stages. The build stage carries a compiler because argon2 is a native module; the runtime stage receives only `node_modules`, the compiled JavaScript and the migration file, and runs as the `node` user.

## Replacing the stub

1. Point `docker-compose.yml` at this service instead of `services/auth-stub`, keeping the same port and the same `JWT_SECRET`.
2. Seed or register users. The Trade REST API needs a token whose `accountId` matches an account it knows about.
3. Change nothing in the Trade REST API and nothing in the Angular UI. If either needs a change, the claims have drifted and `npm run test:parity` will say where.
4. Confirm the cutover by decoding a token and reading `iss`: `auth-stub` came from the fixture, `auth-service` came from here.

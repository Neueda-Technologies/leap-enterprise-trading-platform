# Auth stub

Provided fixture. Node 20, no dependencies, one source file. Used in Sprints 6 and 7, retired in Sprint 8.

## Why it exists

Sprint 6 builds the Trade REST API, and every route on it verifies a JWT. Verifying a token needs something to issue one. Node and NestJS are not taught until Sprint 8, so this stub is given to you rather than built: it issues tokens with exactly the claims the real service will issue, signed with the same algorithm and the same secret, so the Spring Boot verification code is written once and does not change when the real service arrives.

Without it there are two alternatives, and both teach the wrong thing. Hard-coding a token teaches nothing about verification. Turning security off for two sprints and retrofitting it is the habit this programme is trying to break.

## What it is not

No database. No registration. No password hashing. No refresh endpoint. Five users hard-coded with one shared password, compared as plain strings. Every one of those is a critical finding in a real service, and every one of them is fixed in Sprint 8.

It is a fixture, not a deliverable. There is nothing to implement here, no bugs planted in it, and no marks attached to it.

## What to read it for

`src/server.js` is commented as teaching material, because Sprint 6 reads it and does not write it. Three things are worth understanding before Sprint 8:

1. A JWT is three base64url segments joined by dots: header, payload, signature. The payload is encoded, not encrypted. Paste a token into jwt.io and every claim is readable, which is why nothing private goes in one.
2. The signature is what makes the token trustworthy. It is an HMAC of the first two segments using a shared secret. Change one byte of the payload and the signature stops matching.
3. Verification means checking the signature, the expiry, and the algorithm the token asks for, in that order, before reading a single claim. A verifier that decodes the payload first is trusting whatever the client sent.

The signing and verification are written by hand rather than with a library, so all three are visible in about forty lines.

## Routes

| Method | Path | Behaviour |
|---|---|---|
| POST | `/auth/login` | Any of the five demo users with the fixed password. Returns the contract's `TokenResponse`. |
| GET | `/auth/me` | Verifies the bearer token and returns the user it names. |

`/auth/register` and `/auth/refresh` are in the contract and are not implemented here. Sprint 8 implements all four.

## Demo users

| Username | Password | `accountId` |
|---|---|---|
| `demo1` | `Trainee#2026` | 1 |
| `demo2` | `Trainee#2026` | 2 |
| `demo3` | `Trainee#2026` | 3 |
| `demo4` | `Trainee#2026` | 4 |
| `demo5` | `Trainee#2026` | 5 |

Each maps to a trading account by numeric key, 1 to 5, so a token for `demo3` can trade account 3. Seed five accounts with those keys in your Sprint 3 database and all five users work end to end. All five hold the role `CUSTOMER`.

The stub has no database, so it derives each user's `sub` from the username with a name-based UUID (RFC 4122 version 5). The Sprint 8 service runs the identical computation when it seeds its demo users, so `demo1` is the same person to both implementations.

## The token it issues

```json
{
  "sub": "3395aba0-5dde-52cf-b7b6-d1d1c91c2086",
  "accountId": 1,
  "roles": ["CUSTOMER"],
  "iat": 1786042790,
  "exp": 1786043690,
  "iss": "auth-stub"
}
```

Header: `{"alg":"HS256","typ":"JWT"}`. Fifteen-minute lifetime, in seconds since the Unix epoch.

Only `iss` differs from a token the Sprint 8 service issues, and that is deliberate: during the cutover, decoding a token and reading `iss` tells a team which implementation signed it.

A `refreshToken` field is present in the login response so that the body matches the contract. It is random, it is not stored, and there is nothing here to present it to.

## Errors

The same envelope as the rest of the platform, so the Angular UI has one error handler.

| Code | HTTP | When |
|---|---|---|
| `AUTH-401` | 401 | Unknown user, wrong password, missing or invalid token, unknown route |
| `VAL-422` | 422 | Body missing a field or not valid JSON |

Note in the code that the unknown-user case and the wrong-password case fall into one branch. Two different answers would let an attacker confirm which usernames exist before trying a single password.

## Running it

```bash
JWT_SECRET=development-only-shared-secret-change-me node src/server.js

curl -s -X POST http://localhost:3001/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"demo1","password":"Trainee#2026"}'
```

| Variable | Default | Purpose |
|---|---|---|
| `JWT_SECRET` | none, required | HS256 secret. Must match the secret the Trade REST API verifies with. The process exits without it. |
| `PORT` | `3001` | Listen port. |
| `JWT_ISSUER` | `auth-stub` | The `iss` claim. |
| `ACCESS_TOKEN_TTL_SECONDS` | `900` | Token lifetime. |

The port defaults to 3001 so that the stub and the Sprint 8 service can run at the same time, which is what the parity check and a careful cutover both need. The contract puts the auth service on 3000: set `PORT=3000`, or map the container port, wherever the platform expects it there.

Docker:

```bash
docker build -t auth-stub .
docker run --rm -p 3000:3001 -e JWT_SECRET=development-only-shared-secret-change-me auth-stub
```

## Tests

```bash
npm test
```

Node's built-in test runner, nothing to install. Six tests covering the token shape for all five users, the identical failure response for an unknown user and a wrong password, the 422 path, `/auth/me` against a valid token, and its rejection of a missing header, a wrong scheme, a tampered payload and an expired token.

These exist so that a participant can rule the fixture out before spending an afternoon deciding whether their own verification code is wrong. They are not an assessment.

Write a contract parity check of your own alongside the real service in Sprint 8. It signs with both implementations and cross-verifies: a stub token must verify in your service, a service token must verify in the stub, and the claim names, types, algorithm and lifetime must match. A test like that fails the moment either side drifts, which is what turns the cutover into a configuration change rather than a debugging afternoon.

## Retirement, Sprint 8

Sprint 8 builds the real service in `services/auth-service`: registration, argon2 hashing, a Postgres credential store, refresh-token rotation, guards and Jest tests. Point the compose file at that service, keep the same `JWT_SECRET`, and stop starting this one. The Trade REST API and the Angular UI change nothing but configuration. If either needs a code change, the claims have drifted, and the parity test says where.

# Angular UI

Reference implementation of the Sprint 9 component. This is the only part of the platform a
trader ever sees, and it is the first place the asynchronous execution model becomes visible:
the API answers before the fill exists, so the interface has to show an order that has been
accepted but not yet resolved. A UI that renders the POST response as the outcome will show
`NEW` forever and the team will go looking for a bug in the Trade Executor.

The application signs a user in against the Auth service, holds the JWT, attaches it to every
platform request through an interceptor, and reads and writes through the Trade REST API. It
never calls the Fauxnance API, because that would mean shipping an API key to the browser.

Built with Angular 21, standalone components, signals, zoneless change detection and no
NgModules.

## Prerequisites

| Requirement    | Version               | Note                                                   |
| -------------- | --------------------- | ------------------------------------------------------ |
| Node.js        | 20.19+, 22.12+ or 24+ | Angular 21 refuses to start below these                |
| npm            | 10+                   | Installed with Node                                    |
| Docker Compose | any current version   | Runs Postgres, the Trade REST API and the Auth service |

## Run

```bash
npm install
npm start
```

The dev server listens on `http://localhost:4200`. It expects the Trade REST API on `:8080`
and the Auth service on `:3000`, both from the Docker Compose stack at the repository root.

Sign in with a user registered against a seeded account. Without the backend the sign-in form
reports that the service is not reachable, which is the correct behaviour and not a defect in
the UI.

The Trade REST API and the Auth service must allow the browser origin `http://localhost:4200`
in their CORS configuration. A request blocked by CORS reaches the UI as a status 0 with no
body, which is why `toApiError` reports those as "the service is not reachable" rather than
inventing an error code.

## Configuration

Two files, replaced at build time by the `fileReplacements` entry in `angular.json`.

| File                                          | Used by                                            |
| --------------------------------------------- | -------------------------------------------------- |
| `src/environments/environment.development.ts` | `ng serve`, `ng build --configuration development` |
| `src/environments/environment.ts`             | `ng build`, which defaults to production           |

| Key                   | Default                 | Meaning                                                          |
| --------------------- | ----------------------- | ---------------------------------------------------------------- |
| `tradeApiBaseUrl`     | `http://localhost:8080` | Origin of the Trade REST API                                     |
| `authApiBaseUrl`      | `http://localhost:3000` | Origin of the Auth service or the provided Node auth stub        |
| `orderPollIntervalMs` | `2000`                  | Gap between order-history reads while an order is `NEW`          |
| `orderPollAttempts`   | `10`                    | Reads before the ticket stops watching and points at the blotter |

The Node auth stub and the NestJS Auth service implement the same contract and both listen on
3000, so swapping one for the other is a change to `authApiBaseUrl` and nothing else. A team
running both side by side during the Sprint 8 cutover puts the stub on 3001 and points this
key at whichever one it is testing. That single line is the whole acceptance criterion for
"no code change in the Angular UI".

Environment values are compiled into the bundle. Nothing secret goes in them. There is no
Fauxnance key here and there never will be.

The `e2e` suite reads its own settings from the environment: `E2E_BASE_URL`, `E2E_TRADE_API`,
`E2E_AUTH_API`, `E2E_USERNAME`, `E2E_PASSWORD` and `E2E_SYMBOL`.

## Screens

| Screen       | Route         | Endpoints                                                      | Notes                                                                                                                                                                                          |
| ------------ | ------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sign in      | `/login`      | `POST /auth/login`, `GET /auth/me`                             | One error message for every failure. The Auth service returns the same `AUTH-401` body for an unknown user and a wrong password, so the UI must not be more specific.                          |
| Dashboard    | `/dashboard`  | `GET /api/v1/accounts/{id}`, `.../balance`, `.../positions`    | Holder name, cash balance and open positions. The three calls run together. Holdings are not valued: market value needs a live quote and belongs to the Sprint 10 Portfolio and P&L extension. |
| Order ticket | `/orders/new` | `POST /api/v1/orders`, then `GET /api/v1/accounts/{id}/orders` | Read-only account, symbol, side, quantity, limit price. Handles both the `NEW` and the terminal response.                                                                                      |
| Blotter      | `/orders`     | `GET /api/v1/accounts/{id}/orders`                             | Every order, newest first, rejections included. BUY is green, SELL is red, and both carry the word as well as the colour.                                                                      |

`/login` is the only unguarded route. Everything else runs `authGuard`, which redirects to
`/login?redirectTo=...` when no usable access token is held.

## How an order is placed

`POST /api/v1/orders` returns `NEW` from Sprint 7 onwards, and `FILLED` or `REJECTED` in
Sprint 6 where the API still fills inside the request. Both are valid under the contract, so
the ticket handles both without a configuration switch.

1. Generate an idempotency key and post the order.
2. A terminal status in the response is displayed as the outcome. Sprint 6 stops here.
3. A `NEW` status puts the ticket into a pending state and starts polling
   `GET /api/v1/accounts/{id}/orders` every two seconds.
4. The first non-`NEW` status for that order id is displayed and polling stops.
5. If the attempts run out, the ticket says the order is still working and points at the
   blotter. The order is recorded either way. Nothing is lost.

Two rules in `OrderService` and `OrderTicket` are worth reading before writing your own.

Poll order history, never the placement endpoint. Re-posting with the same idempotency key
returns `ORD-409`, and re-posting with a new one places a second order. The contract says this
in as many words.

The idempotency key is generated once per order and reused only when the request never
reached the server, which the UI recognises as a status 0. Once the server has answered, the
key is discarded, whatever the answer was. A key regenerated on every retry duplicates orders;
a key reused after a response collides with the unique constraint on
`orders.idempotency_key`.

## Authentication

| Piece             | File                                            | Responsibility                                                                                           |
| ----------------- | ----------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `AuthService`     | `src/app/core/services/auth-service.ts`         | `login`, `logout`, `isAuthenticated`, `getToken`, `refresh`, and the account key the session may address |
| `authInterceptor` | `src/app/core/interceptors/auth-interceptor.ts` | Attaches the bearer token, refreshes once on a 401, retries, and signs the user out if the refresh fails |
| `authGuard`       | `src/app/core/guards/auth-guard.ts`             | Keeps signed-out users off the authenticated routes                                                      |

Four decisions in that code are deliberate.

The token goes only to `tradeApiBaseUrl` and `authApiBaseUrl`. An interceptor that adds the
header to every outbound request hands the session token to any third party the application
calls.

`/auth/login`, `/auth/register` and `/auth/refresh` are `security: []` in the contract and get
no header.

One refresh runs at a time. Six concurrent 401s firing six refreshes means five of them
present a token the first one has already consumed, and the Auth service treats a reused
refresh token as theft and revokes the chain.

A failed refresh clears the session and navigates to `/login`. Retrying without that limit is
an infinite loop the moment the Auth service is down.

Tokens are held in `localStorage`, which means any script on this origin can read them, so an
XSS defect becomes a stolen session. The production answer is an httpOnly, SameSite cookie
set by the Auth service. The capstone uses `localStorage` because the Auth service issues
bearer tokens rather than cookies, and because seeing the token in developer tools is part of
what Sprint 8 teaches. Access tokens live fifteen minutes, which bounds the damage.

The guard and `isAuthenticated` are usability controls, not security controls. The bundle is
public. Every authorisation decision is taken by the Trade REST API, which verifies the
signature on every `/api/v1/**` route.

## Typed models

`src/app/core/models/trade-api.ts` and `auth-api.ts` are hand-written from the OpenAPI
contracts. They are hand-written here so that the reference implementation reads without a
generation step, and because the comments on each field carry the reasoning that a generated
file would drop.

Generate them instead if you prefer the contract to be the only source of truth:

```bash
npx @openapitools/openapi-generator-cli generate \
  -i ../docs/contracts/trade-api.yaml \
  -g typescript-angular \
  -o src/app/core/api/trade \
  --additional-properties=ngVersion=21.0.0,providedInRoot=true,fileNaming=kebab-case
```

That produces one interface per schema and one injectable client per tag, `OrdersService` and
`AccountsService`, with the same field names this file declares. The generator needs a Java
runtime. Add the command to CI so that a contract change breaks the build rather than
production. Do not edit generated output: regenerate it.

## Test

```bash
npm test          # unit tests, headless, single run
npm run test:watch
```

Vitest with jsdom, through the Angular `@angular/build:unit-test` builder. No browser is
needed and no Karma configuration exists.

| Suite                                        | Covers                                                                                                                                               |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `core/services/auth-service.spec.ts`         | Token storage, expiry, logout, single-flight refresh, session clearing on a rejected refresh                                                         |
| `core/interceptors/auth-interceptor.spec.ts` | Header attachment, the public routes and third-party origins that get no header, refresh and retry on a 401, sign-out when the refresh fails         |
| `core/guards/auth-guard.spec.ts`             | Allowing an authenticated navigation, and the redirect that carries `redirectTo`                                                                     |
| `features/order-ticket/order-ticket.spec.ts` | Field validation against business rules 4 and 5, the read-only account, the pending state on a `NEW` response, and a fresh idempotency key per order |

### End-to-end

```bash
npm run e2e:install   # once, downloads the Chromium build Playwright drives
npm run e2e
```

Playwright starts the dev server if one is not already running. It does not start the backend.
Bring that up first:

```bash
docker compose up -d
```

Specs that need live services check for them and skip with a message when they are absent, so
a run on a laptop with nothing else running reports skips rather than a wall of connection
errors. The route-protection specs in `e2e/login.spec.ts` need no backend and always run.

| Spec                      | Covers                                                                                                                                                                                        |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `e2e/login.spec.ts`       | Guard redirects, a failed sign-in, a successful sign-in, return to the requested screen, sign-out                                                                                             |
| `e2e/place-order.spec.ts` | Read-only account, client-side rejection of a zero quantity and a zero price, placing an order and reporting either the pending or the terminal status, a rejected order still being recorded |
| `e2e/blotter.spec.ts`     | Table columns, an empty state rather than a blank screen, BUY and SELL rendering, filtering by status through the API query parameter                                                         |

The order-placement spec accepts `NEW`, `FILLED` or `REJECTED`. Asserting only `FILLED` would
make the suite fail the week Kafka arrives, which is the wrong signal from a test.

## Container

```bash
docker build -t etp-ui .
docker run --rm -p 4200:80 etp-ui
```

Two stages: Node builds the bundle, nginx serves it. `nginx.conf` sets the single-page fallback
so that reloading `/orders/new` returns `index.html` rather than a 404, caches the
content-hashed assets for a year, and refuses to cache `index.html`.

Sprint 11 deploys the same build output to S3 behind CloudFront, so this image is for local
parity rather than for production. The API origins are compiled into the bundle, so an image
built for one environment cannot be repointed at another by an environment variable.

## Layout

```
src/
  app/
    app.config.ts            providers: router, HttpClient, the interceptor
    app.routes.ts            four routes, three of them guarded, all lazily loaded
    core/
      api-error.ts           HttpErrorResponse to a message, one handler for both contracts
      jwt.ts                 unverified claim decode, used for expiry and the account key
      validators.ts          whole number, greater than zero, two decimal places
      models/                interfaces from the OpenAPI contracts
      services/              AuthService, AccountService, OrderService
      interceptors/          bearer token, 401 refresh and retry
      guards/                authGuard
    features/
      login/ dashboard/ order-ticket/ blotter/
  environments/              API origins and polling settings
  styles.css                 design tokens and shared component styles
  testing/                   test-only helpers
e2e/                         Playwright specs and the service probe
```

There is no component library. Every style rule is plain CSS in `src/styles.css` and four
small component stylesheets, so a participant can read the whole visual layer.

## Decisions taken here, beyond the contracts

| Decision                                                                             | Reasoning                                                                                                                                                   |
| ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tokens in `localStorage`                                                             | The Auth service issues bearer tokens, not cookies. Documented above with the trade-off.                                                                    |
| Polling rather than a socket for the fill                                            | Neither contract offers a push channel to the browser. Ten reads at two seconds covers a local executor with room to spare.                                 |
| `AccountResponse.cashBalance` is shown without a currency symbol on the order ticket | The account schema carries no currency. `BalanceResponse` does, and the dashboard uses it there.                                                            |
| Status filter on the blotter                                                         | The history endpoint declares an optional `status` parameter, and the blotter is the only screen that can use it.                                           |
| Symbol pattern `^[A-Za-z0-9.:_-]+$`                                                  | Accepts every symbol scheme the contract lists: `ACME`, `INFY.NS`, `FX:EURUSD`, `X:BTCUSD`. The API is still the authority on whether an instrument exists. |
| Quantity capped at the int32 ceiling                                                 | The contract types quantity as `int32`. This is a type limit, not a business limit.                                                                         |
| `redirectTo` is accepted only as a path on this origin                               | A query parameter the user controls, followed blindly, is an open redirect.                                                                                 |

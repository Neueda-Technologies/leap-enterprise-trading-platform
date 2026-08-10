# Sprint 9: the trading UI

Every API this application consumes already exists, and your team wrote all of it. The
schema is yours from Sprint 3, the domain rules from Sprint 5, the Trade REST API from
Sprint 6, the executor and the bus from Sprint 7, the Auth service from Sprint 8. Nothing in
this sprint is blocked on a service somebody else has to finish.

That is why the front end is built last, and it is not a scheduling convenience. A screen
written against an API that does not exist yet is a screen written against an API somebody
imagined, and the two disagree the week the real one arrives. Building it now means every
call you make is a call you can run, and every failure you render is a failure you can
provoke.

It also means this is the week the platform stops being a set of services and becomes a
product. Until now a trader could not place an order. From Friday they can.

One property of the platform becomes visible here for the first time, and it is the thing
most teams get wrong. Execution is asynchronous. The Trade REST API answers before the fill
exists. An interface that renders the response to `POST /api/v1/orders` as the outcome shows
`NEW` and stops, and the team goes looking for a defect in the Trade Executor that is not
there.

## What you deliver

| Deliverable | Where it lives |
|---|---|
| Typed clients generated from both contracts | `src/app/core/api/`, committed |
| Sign-in against the real Auth service | `src/app/features/login/` |
| Dashboard: holder, cash and open positions | `src/app/features/dashboard/` |
| Order ticket with client-side validation and full error rendering | `src/app/features/order-ticket/` |
| Blotter with status badges | `src/app/features/blotter/` |
| One interceptor attaching the bearer token | `src/app/core/interceptors/` |
| Route guards and the redirect | `src/app/core/guards/` |
| The mapping from every catalogue code to a readable message | `src/app/core/errors/` |
| Unit tests, including the two named interceptor cases | beside the code, as `*.spec.ts` |
| Three Playwright journeys | `e2e/` |
| The manifest telling the check harness your names | `manifest.env` |

The scaffold gives you the workspace, the build, the dependency set, the generator
configuration, the Playwright configuration and the harness. Every component, service,
guard, interceptor, route and test is yours to write. There are no stubs to fill in.

## Standalone components and signals

No NgModules. Not in the application you write, not in the shell that ships, nowhere. Angular
has had standalone components as the default since version 17, and an `NgModule` in a
codebase this size buys you a second place to declare things and nothing else.

State that a template reads is a signal. State that a template derives is a `computed`.
Anything that has to happen when state changes is an `effect`, and if you are reaching for
one to set another signal, the answer was a `computed`.

The one place observables stay is `HttpClient`, because that is what it returns and what the
generated clients return. Take the response, put it in a signal, and let the template read
the signal. A template full of `| async` and a component full of subscriptions that nobody
unsubscribes are the two habits this sprint is meant to break.

## The typed clients are generated

The criterion is that your API clients are generated from `contracts/`, not written by hand.
This is the one part of the sprint where the instruction is exact.

```bash
cd sprint-09-trading-ui
npm run generate
```

That reads `openapitools.json` and runs the OpenAPI Generator twice: `trade-api.yaml` into
`src/app/core/api/trade`, `auth-api.yaml` into `src/app/core/api/auth`. Every option lives in
that file, including the pinned generator version, so that two people on the team generate
the same output and the harness regenerates with exactly your settings. The generator runs on
the JVM and needs the JDK you have had since Sprint 5.

One option in that file needs explaining, because you should not accept a validation being
switched off without knowing why. `skipValidateSpec` is set because the generator's 3.1
validator asks for `info.license.identifier`, which the OpenAPI specification makes optional
and the contracts do not carry. The contracts are correct and are not yours to edit.

Hand-writing the interfaces instead is rework the first time and drift every time after it.
The first cost is a morning of typing that a command does in four seconds. The second cost is
the one that hurts: when `trade-api.yaml` changes a field, a generated client stops
compiling at every call site that used it, and a hand-written one keeps compiling and starts
returning `undefined` at runtime. That is the whole reason the contract exists.

### The generated output is committed

Committed, not git-ignored, and `.gitignore` says so in as many words.

The trade-off is real either way. Ignoring generated code keeps the diff small and makes the
contract the only source of truth on disk. Committing it means a clone builds with no Java
runtime and no network, means a contract change arrives as a diff a reviewer can read, and
means the harness can tell a current client from a stale one. This platform commits it, for
the third reason more than the first two: a generated artefact nobody can see is a generated
artefact nobody notices going stale.

Committing it carries one obligation. `npm run generate` after every contract change, and
commit the result in the same commit as the code that adapts to it. The harness regenerates
both clients into a temporary directory and diffs them against yours, so a contract that has
moved ahead of the committed client is a named failure with the differing files listed.

### The generated code is not style-reviewed

Nobody reviews the formatting, the naming or the shape of anything under
`src/app/core/api/`. It is machine output. Do not reformat it, do not run Prettier over it,
and do not tidy a name you dislike: the next generation reverts all three and the diff that
should have shown a contract change shows two hundred lines of whitespace instead.

Never edit a file in there. When the generated shape is awkward to consume, wrap it in a
service of your own in `src/app/core/services/`, which is where your reviewers will look for
it anyway. The harness reads the generator's own file list and fails if a file appears inside
the generated tree that the generator did not write.

## The interceptor, and the half of it that is a security control

One functional interceptor, registered once in `withInterceptors`, is the only place in this
application that sets an `Authorization` header. No component and no service builds that
header for itself. Doing it in each service means the day somebody adds a service and forgets
is the day a call goes out unauthenticated, and the failure is a 401 nobody can explain.

The rule has two halves.

Attach the bearer token to your own platform APIs: the Trade REST API, and the protected
route on the Auth service. Not to `/auth/login`, `/auth/register` or `/auth/refresh`, which
are `security: []` in the contract and take no header.

Attach it to nothing else, and decide by comparing the outgoing URL against the origins you
configured, never by excluding a list of hosts you happened to think of. An allow list fails
closed when somebody adds a new third party. A deny list fails open, silently, on the day
somebody adds one you did not list.

The second half is the security control, and it is worth being blunt about the failure. An
interceptor that adds the header to every outbound request hands a live session token to
whatever host that request was going to. The token is a bearer credential: whoever holds it
is the customer until it expires. It arrives in that third party's access log, their
analytics pipeline and their error tracker, and it stays in all three long after your fifteen
minutes are up. That is a reportable security incident with a named customer attached, not a
bug to fix in the next sprint. The Fauxnance API is the case closest to hand, because Sprint
4 taught you to call it and this application must not, but the rule is about every host that
is not yours.

Two unit tests are assessed by name: one that a request to your API carries the header, one
that a request to a third-party origin does not. The harness runs your suite, reads the names
of the tests that ran and looks for both, using the patterns in `manifest.env`.

## Route guards

`/login` is the only route an unauthenticated visitor may reach. Every other route runs a
guard, and a signed-out visitor is redirected to the sign-in route carrying where they were
going, so that signing in returns them there rather than dropping them on a dashboard.

Redirect. Do not render an empty screen, and do not silently show a shell with no data: a
user who has been told nothing will retry, then raise a ticket.

Accept a return address only if it is a path on this origin. A parameter the user controls,
followed without checking, is an open redirect, and an open redirect on a trading login page
is a phishing kit somebody else assembles for free.

Say this out loud once, because it is asked at the review: the guard is a usability control,
not a security control. The bundle is public and every route in it is readable. Authorisation
is the Trade REST API's decision, taken by verifying the token signature on every
`/api/v1/**` call and comparing the `accountId` claim against the account addressed.

## The order ticket

Validate before you submit. Quantity is a whole number greater than zero. Price is greater
than zero with at most two decimal places. The symbol matches the shape the contract allows.
The account is the one the token says this session may trade, rendered read-only, because an
account field the user can edit is an authorisation decision moved into the browser.

Client-side validation is not enforcement. Business rules 1 to 8 live in the Trade REST API
and stay there. The form exists so that the obvious mistakes never reach the wire, and the
error rendering exists because the rest of them will.

### Rendering the catalogue is a deliverable

Both contracts return one envelope, `{ "errorCode": ..., "message": ... }`. Branch on
`errorCode`. Never branch on the `message`, which is written for a developer reading a log
and changes without notice, and never show it to a trader as the explanation.

Every code in the two catalogues gets a human-readable rendering. All eight of them.

| Code | Contract | What the user has to be told |
|---|---|---|
| `ACC-404` | trade | The account could not be found |
| `ACC-403` | trade | This account is not active, or is not the one this sign-in may trade |
| `INS-404` | trade | The instrument is not one that can be traded |
| `ORD-400` | trade | There is not enough cash for this order |
| `ORD-409` | trade | Not enough of the holding to sell, or this order has already been placed |
| `VAL-422` | both | A field is not acceptable |
| `AUTH-401` | both | The session has expired or the sign-in was refused |
| `AUTH-409` | auth | That username is already taken |

The wording above is the meaning, not the copy. Write sentences a trader can act on.

Two cases are not in either catalogue and still reach the screen. A response the browser never
received, which arrives as status 0 and is almost always a service that is not running or a
CORS rule that does not allow `http://localhost:4200`. And a code you have never seen, which
needs a fallback sentence rather than a blank panel.

Treat this as a mapping with a completeness property, not as a switch statement you extend
when somebody reports a blank screen. The harness reads the codes straight out of the
contracts and names any that appear nowhere in your mapping. An unmapped code surfacing raw
at the review, or as an empty box, is a finding.

## The blotter

Every order for the account, newest first, rejections included. A blotter that hides rejected
orders is worse than no blotter: the rejection is the record that the desk tried and was
refused, and it is the first thing anyone looks for when a customer rings.

Four statuses, four badges: `NEW`, `FILLED`, `REJECTED`, `CANCELLED`. Each badge carries the
word as well as the colour, because roughly one man in twelve cannot separate red from green.

### An order sitting at `NEW` is normal

`NEW` is the working state. The Trade REST API validated the order, wrote it and published
it, and the Trade Executor has not resolved it yet. The order is recorded. Nothing is lost.
It is not an error state, it is not a stalled request, and it is not a defect in Sprint 7.

Two consequences you have to design for.

The screen cannot be a snapshot taken once. Something has to bring the row up to date:
re-reading order history on an interval while anything is at `NEW`, a refresh the user can
press, or both. Neither contract offers a push channel to the browser, so there is no third
option that avoids the question.

Whatever you choose, bound it and be able to defend the numbers. An interval that never stops
is a request every two seconds for as long as the tab is open, which is a load test you did
not mean to run. Stop when nothing is at `NEW`, stop after a sensible number of attempts, and
say on screen that the order is still working rather than pretending it has finished.

One rule about what to poll. Re-read order history. Never re-post the order: the same
idempotency key returns `ORD-409`, and a new one places a second order.

## The Playwright deliverable

Three journeys against your running stack, in `e2e/`. The names in `manifest.env` are the
defaults, and the harness runs each file separately.

| Journey | Default file | Covers |
|---|---|---|
| Sign in | `e2e/login.spec.ts` | The guard redirect, a refused sign-in, a successful sign-in, arriving where you were going |
| Place an order | `e2e/place-order.spec.ts` | The read-only account, a rejection before submission, a placed order and whatever status came back |
| View history | `e2e/blotter.spec.ts` | The columns, the badges, an empty state rather than a blank screen |

These run against your real services. That is the point of them: unit tests already cover the
pieces, and an end-to-end test that talks to a stub proves nothing about integration.

Each journey starts from a clean sign-in and leaves nothing behind that another journey needs.
No journey may depend on another having run first, and none may depend on running in a
particular order. Playwright gives each test a fresh browser context, so the way this rule
gets broken is with shared state on your side: a token stashed in a module variable, an
account seeded by the first spec and read by the second, an order the history spec expects
because the order spec placed it. The harness runs each of the three files in its own
process, so a journey that only passes when its neighbour ran first fails here rather than at
the review.

Order-placement assertions accept `NEW`, `FILLED` or `REJECTED`. A spec that asserts `FILLED`
fails the week the executor is switched on, which is the wrong signal from a test.

Read the settings your suite needs from the environment, using these names, and your specs
and the harness stay on one set of credentials.

| Variable | Meaning |
|---|---|
| `E2E_BASE_URL` | Where the application is served |
| `E2E_TRADE_API` | Trade REST API origin |
| `E2E_AUTH_API` | Auth service origin |
| `E2E_USERNAME`, `E2E_PASSWORD` | A user your Auth service can authenticate |
| `E2E_ACCOUNT_ID` | The account that user trades |
| `E2E_SYMBOL` | A tradable instrument your Sprint 3 seed holds |

Give the sign-in form's username field, password field and submit button a stable
`data-testid`. The harness drives that form with the selectors in `manifest.env` to run the
guard and bearer-token probes, and a probe that finds a control by the text on it breaks the
first time somebody rewrites a label.

## Nothing secret in the bundle

`npm run build` produces files that every browser downloading this application receives.
There is no private part of a front-end build. Minification is not obfuscation, and a
`.map` file is the source back again.

Three things must not appear in the output, and the harness greps for each of them.

| Pattern | Why |
|---|---|
| `x-api-key`, `api_key`, `api-key`, `fauxnance` | A market-data key in the bundle is a key published. Revoke it, do not delete it |
| An `execute-api.<region>.amazonaws.com` host | This application never calls the market-data API. Prices reach the browser through your own services |
| `jwt_secret`, a secret assigned a long literal, a three-part JWT written into source | A signing secret in the browser lets any reader mint a token the whole platform accepts |

When the repository root `.env` is present, the harness also searches the bundle for the
literal values of your own key and signing secret, which catches a value pasted in under a
name none of those patterns would match. It names the variable and never prints the value.

The rule underneath all three is one sentence: the Angular application never calls the
Fauxnance API. Prices reach the browser through a service of yours that holds the key
server-side, which is exactly what the market-data poller was for.

## The toolchain

Angular 21, standalone components, signals, zoneless change detection, Vitest through the
Angular unit-test builder, and Playwright.

```bash
cd sprint-09-trading-ui
npm ci                 # installs exactly the tree the lock file names
npm run generate       # writes the typed clients from contracts/
npm start              # dev server on 4200
npm run build          # production bundle, into dist/trading-ui/browser
npm test               # unit suite, headless, single run
npm run e2e:install    # once, downloads the browser Playwright drives
npm run e2e            # the journeys, against your running stack

scripts/check.sh       # the acceptance harness
scripts/check.sh --live
```

Node 20.19, 22.12 or 24 and above. Angular 21 refuses to start below those. A JDK for the
generator, which you have from Sprint 5.

Commit `package-lock.json`. It ships with the scaffold and it is what makes a teammate's
build the build you tested.

### The scaffold

```
package.json           the dependency set and the scripts
angular.json           the build, serve and unit-test targets
tsconfig*.json         strict TypeScript, strict templates
openapitools.json      the generator configuration, one entry per contract
playwright.config.ts   the journeys, with the base URL in one place
src/main.ts            a bootstrap that compiles, and nothing else
src/environments/      the two API origins, and no secrets
src/app/               empty directories, each with a README saying what belongs in it
e2e/                   your three journeys
scripts/check.sh       the acceptance harness
manifest.env           the names the harness reads
```

`src/app/` ships as directories with READMEs and no code. Reorganise them if your design says
something else, and tell the harness what you chose in `manifest.env`.

The bootstrap in `src/main.ts` exists so that `npm ci && npm run build` succeeds on a fresh
clone. It is not the shape of the finished application: move the providers into an
`ApplicationConfig`, write a real root component, and declare your routes.

### The two API origins

`src/environments/environment.ts` is compiled into the production bundle and
`environment.development.ts` into the dev server build, swapped by the `fileReplacements`
entry in `angular.json`. Keep the two in step: a key added to one and not the other is a
runtime `undefined` the compiler cannot see.

Those two files are the only place an API address is written. The Auth service and the
retired Node auth stub implement the same contract and both listen on 3000, so pointing this
application at one or the other is a change to one line and nothing else. That is the whole
of the "no code change in the Angular application" criterion from Sprint 8.

## The harness

`scripts/check.sh` runs in two modes and reads every name it needs from `manifest.env`.

Static mode installs from the lock file, builds the production bundle, confirms both
generated clients are on disk and carry the generator's own metadata, regenerates them into a
temporary directory and diffs, confirms something outside the generated tree imports them,
runs your unit suite and reads the names of the tests that ran, checks every code in the
contracts against your mapping, and greps the built files for a key, a secret and the
market-data address.

Live mode needs your whole stack up and running, and starts nothing itself. It confirms the
three services answer, runs each journey in its own process, then drives your sign-in form
twice: once from a clean context straight at a guarded route, to watch the redirect, and once
signed in with a recording of every request the page makes, to see where the bearer token
went and where it did not. The probe it writes into `e2e/` is deleted when the harness exits.
Do not commit it.

Live mode signs in several times over: at least once per journey and twice in the probes. If
your Auth service throttles the login route, as Sprint 8 asked it to, the later attempts come
back refused and read here as broken journeys. Tell the harness about the throttle with
`LOGIN_THROTTLE_COOLDOWN_SECONDS` in `manifest.env` and it waits out your window before each
sign-in. Do not weaken the throttle to make a harness pass.

Both modes explain every skip and name it. A skip is honest. A green run against something
that was not there is not.

## Acceptance criteria

These are the criteria your instructor assesses against.

1. Sign-in works end to end against the real Auth service.
2. The interceptor attaches the bearer token to every platform API call, and attaches it to
   no Fauxnance or third-party call.
3. Route guards block unauthenticated access and redirect.
4. The API clients are generated from `contracts/`, not hand-written.
5. The order ticket validates before submission.
6. Every error code in the catalogue renders as a readable message.
7. The blotter shows status badges and handles an order sitting at `NEW`.
8. Playwright covers signing in, placing an order and viewing history.
9. No API key and no secret is present in the built bundle.

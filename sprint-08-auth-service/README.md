# Sprint 8: the auth service

Five services in this platform need to know who is calling and which account
that caller may act on, and none of them should hold a password to find out. A
password that lives in the Trade REST API leaks the day that service has an
injection defect, and a hashing routine copied into the Trade Executor gets
upgraded in one of the two places. This sprint builds the one component that
ever sees a credential, and gives every other component a signed statement of
identity it can check on its own.

That is why authentication is a service rather than a library. One process owns
registration, login, hashing and the token lifecycle, and every other process
verifies a signature with no network call and no shared database. The stub in
`services/auth-stub` has stood in for that process since Sprint 6, with no
database, no hashing and no refresh. This sprint retires it.

## A short week

Two SME cloud sessions run on Monday and Tuesday, so the order of the work
decides whether it fits. Take registration and login first, with the hashing and
the uniform failure built in rather than retrofitted. Then the guard and
`/auth/me`, then refresh, then the cutover, which needs the rest of the stack
up. Fill in the security review as each part lands.

## What you deliver

| Deliverable | Where it lives |
|---|---|
| Four endpoints implementing `contracts/auth-api.yaml` | the module tree you design |
| A credential store with hashed passwords | your migration or bootstrap, plus the repository that reads it |
| Access and refresh token issuance, and refresh token storage | as above |
| A guard protecting `/auth/me` | as above |
| Jest suites, including the guard paths named below | alongside the code, as `*.spec.ts` |
| A multi-stage `Dockerfile` | this folder |
| Your service in the root `docker-compose.yml`, with the stub removed | repository root |
| The OWASP review, filled in | `security-review/` |
| The manifest telling the check harness your names | `manifest.env` |

No starter code and no project skeleton ships. Deciding how this service is
decomposed, and where the verification happens inside it, is most of what the
sprint assesses.

## The engineering contract

Set one project up in this folder. Its internals are yours. Nine things are
fixed, because the harness, the compose stack and your teammates depend on them.

- One NestJS project rooted in this folder, on Node 20 or later and TypeScript,
  where `npm ci`, `npm run build` and `npm test` all succeed on a machine that
  has never seen your code. Commit `package-lock.json`: `npm ci` installs
  exactly the tree it names.
- Sources under `src/`, or under whatever you declare in `SRC_DIR` in
  `manifest.env`, with the specs as `*.spec.ts` beside the code they cover.
- The four operations in `contracts/auth-api.yaml`, at the paths, verbs, status
  codes and bodies it fixes, answering on port 3000.
- Access tokens signed HS256 with `JWT_SECRET`, carrying exactly `sub`,
  `accountId`, `roles`, `iat` and `exp`, plus the `iss` the contract defines.
- Passwords stored with argon2id, or bcrypt at cost 12 or above, and never
  written to a log.
- Jest covering the guard, including the expired-token and wrong-signature
  paths, with names the patterns in `manifest.env` reach.
- The OpenAPI document generated from your code and served by the running
  service, at the two paths declared in `manifest.env`.
- `JWT_SECRET`, the database connection and every other value that differs
  between a laptop and a container read from the environment at runtime, and
  present in no committed file.
- A multi-stage `Dockerfile` of your own design here, and the service joined to
  the root `docker-compose.yml` in place of `auth-stub`, so that retiring the
  stub is a configuration change in your Sprint 6 service rather than a code
  change in it.

```bash
cd sprint-08-auth-service
npm install                  # first run, and whenever you add a dependency
npm run build
npm test

scripts/check.sh             # and --live once your stack is up
```

## The contract is the specification

`contracts/auth-api.yaml` was written before either implementation existed and
it binds both. Four operations, with paths, verbs, status codes and bodies
fixed.

| Method | Path | Protected | Success | Documented failures |
|---|---|---|---|---|
| POST | `/auth/register` | no | 201 `UserResponse` | `AUTH-409`, `VAL-422` |
| POST | `/auth/login` | no | 200 `TokenResponse` | `AUTH-401`, `VAL-422` |
| POST | `/auth/refresh` | no | 200 `TokenResponse` | `AUTH-401`, `VAL-422` |
| GET | `/auth/me` | bearer token | 200 `UserResponse` | `AUTH-401` |

Registration issues no tokens, because an unauthenticated route that mints a
session is an authentication bypass as soon as it has its first defect. It does
not create a trading account either: accounts are owned by the Sprint 3 schema.
Every failure leaves in the platform envelope, `{"errorCode": ..., "message":
...}` and nothing else, so that Sprint 9 keeps one error handler for the whole
platform.

## The claim set, exactly

The token payload is not a place to put things that might be useful later. Every
claim in it is a field a consumer can start depending on, and every consumer
that depends on one is a service that breaks when you remove it.

| Claim | Type | Meaning |
|---|---|---|
| `sub` | string | The user identifier, a UUID. Stable for the life of the user, and not the username, because a username can change |
| `accountId` | integer | The numeric trading account key, `ACCOUNTS.id`. The Trade REST API compares it against the account in the request and answers `ACC-403` when they differ |
| `roles` | array of string | `CUSTOMER` or `ADMIN`. Always present, never empty |
| `iat` | integer | Issued at, seconds since the Unix epoch |
| `exp` | integer | Expiry, seconds since the Unix epoch. Fifteen minutes after `iat` |

Those five are assessed. The contract defines one more, `iss`, carrying
`auth-service` here and `auth-stub` in the fixture, so that during the cutover a
team can decode a token and see which implementation signed it. Consumers must
not require a particular value for it.

Anything beyond those six is a finding, not a bonus. An email address in the
payload is an email address published to every holder of the token, because the
payload is base64 and not encryption: paste one into any decoder and read it.
The harness decodes an access token and fails on any claim outside the set,
because removing one after Sprint 9 has generated a client from it is not a
configuration change.

## Password storage

Store passwords with argon2id, or with bcrypt at cost 12 or above. Never MD5,
never SHA-256, never an unsalted digest of any kind. A general-purpose hash is
built to be fast, and fast is the one property a password hash must not have: a
modern GPU runs SHA-256 in the billions per second, so a stolen table of those
digests is a stolen table of passwords by the weekend. The cost factor is a
decision you make and defend. Pick values that make one verification take on the
order of a tenth of a second on the hardware you deploy to: too low and an
offline attacker gets the same speedup you did, too high and your login route is
the cheapest denial-of-service target in the platform.

Never log a password. The ways one reaches a log are all indirect: an error
object serialised whole, a request body dumped by a debug interceptor, a DTO
printed in a stack trace. Two habits make the rule structural. Log through one
logger that redacts by key name at any depth, and never hand a whole request
body to a log call. The harness reads your sources for a log call that names a
credential field, which catches the direct case and none of the indirect ones.
The indirect ones are what the review asks about.

## Refresh rotation

An access token cannot be withdrawn. It is verified by signature alone, so
fifteen minutes is the size of that compromise. The refresh token is the
opposite: opaque, stored, revocable, and the reason a user is not asked for a
password every quarter of an hour.

The requirement for this cohort is that every refresh issues a new refresh
token, so a client still presenting the value it was given at login is
presenting a value the service has stopped issuing. Revoking the presented token
is optional here. If you build it, that token is dead in your store before the
response is written and a second presentation answers `AUTH-401`. If you do not,
write the decision and the risk it accepts in the security review, and declare it
in `manifest.env` so that the harness asserts what you built.

Reissue on its own defends against a stolen token used once. Suppose one is
taken from a log, from browser storage, or from a proxy that recorded a request
body. The real user refreshes and carries on with the new value, and what the
thief holds is no longer the one the session runs on. What is missing without
revocation is that the old value still works: both parties refresh, both hold
live sessions, and nothing in the service can tell there are two of them.

Revocation closes that. Exactly one of the two can use the token, and the other
presents one that has already been exchanged. That presentation is the alarm,
because either a client repeated a request or somebody stole a token and the
service cannot tell which. The contract treats it as theft: revoke every live
refresh token for that user, answer `AUTH-401`, and you have a record of when
the two diverged. Store a hash of the refresh token rather than the token either
way, so that read access to your database is not session takeover.

## One answer for every failure

An unknown username and a wrong password get the same status, the same body and
comparable timing. This is the requirement most often failed by accident, and it
fails in three distinct ways.

**The body.** `AUTH-401` with the message `Unauthorised`, for an unknown user, a
wrong password, an expired token, a wrongly signed token and a malformed header.
A helpful message tells an attacker which half of the credential pair was wrong.

**The status.** 401 for all of them. A 404 for an unknown user and a 401 for a
bad password is the same disclosure written in the status line.

**The timing.** If the unknown-user path returns as soon as the lookup misses it
answers in a millisecond, while the wrong-password path spends a tenth of a
second verifying a hash. An attacker with a username list and a stopwatch reads
your customer base off the response times without guessing a password. Make both
paths do the same work: where the username is not found, verify the supplied
password against a fixed dummy hash of the same algorithm and the same
parameters, discard the result and return the same failure.

The harness times both paths and applies two tests. The absolute threshold is
generous, because a laptop under load and a cold connection pool each move a
response by tens of milliseconds. The second is on the shape rather than the
size: one path taking twice as long as the other is an early return even when
both numbers are small, which is what happens on hardware fast enough to run an
argon2 verification inside the threshold. Failing either is proof of an early
return, and passing both is not proof of constant time. The probe is a burst of
failed logins from one address, so it collides with a login throttle. Build the
throttle and declare it with `THROTTLE_COOLDOWN_SECONDS` and
`UNIFORM_TIMING_ATTEMPTS`: a throttle limits how fast an attacker can use an
oracle you left open, and does not close it.

## Replacing the stub

The acceptance statement is that the Trade REST API needs no code change. Not a
small one, and not only a configuration class: no Java changes. That is
achievable because both implementations sign HS256 with the same `JWT_SECRET`
and issue the same claims, so a token from either verifies with the code written
in Sprint 6 against the fixture.

| Change | Where |
|---|---|
| The compose service that answers on the auth port becomes yours, and the `auth-stub` service is removed | root `docker-compose.yml` |
| Your service reads the same `JWT_SECRET` the Trade REST API verifies with | root `.env`, passed through compose |
| The Trade REST API's issuer setting, if it pins one, names your issuer instead of the stub's | that service's configuration, from the environment |
| The database connection for the credential store | your service's environment |

Nothing in that table is a Java file. If your Trade REST API needs a code change
to accept a token from this service, something in it is coupled to the fixture
rather than to the token: a hard-coded issuer string, a claim read with a name
the stub happened to use, or a verifier that decodes the payload before checking
the signature.

The stub's development secret is published in its own README, so anyone who has
read this repository can mint a token your consumers accept for as long as that
secret is in use. Keeping it is defensible in a training stack; rotating it once
the stub is gone is the better habit. Declare which you chose under
`STUB_SECRET_EXPECTATION` in `manifest.env`.

## Tests

Jest, with the Nest testing utilities, running without a database and without an
HTTP server. This is the service where a defect is a breach rather than a bug,
so the suite is a deliverable. The guard is assessed specifically, and two paths
through it are named.

| Path | What the test proves |
|---|---|
| An expired token | A token that was valid, signed by you, with an `exp` in the past, is refused. A guard that checks the signature and forgets the clock accepts every token it ever issued, for ever |
| A wrong signature | A well-formed token whose signature does not match the key is refused before any claim is read. This is the test that catches a verifier that decoded first and verified afterwards |

Make them fail for the right reason. Build the expired case by signing a genuine
token with a past `exp`, not by corrupting the payload, which the signature
check refuses first and which therefore passes against a guard with no expiry
check at all. Build the wrong-signature case by signing a genuine, unexpired
token with a different key.

The harness runs your suite, reads the names of the tests that ran, and looks
for those two cases among the specs whose path matches `GUARD_SPEC_PATTERN`.
Name your tests as you like and correct the patterns if the defaults do not
reach them. Beyond the guard, expect to be asked at the review for tests
covering the identical failure for an unknown user and a wrong password, and the
reissue on refresh.

## OpenAPI, served by the running service

The running service publishes its own OpenAPI document, generated from the
decorators on your controller and your DTOs. A YAML file maintained by hand
beside the code drifts within a fortnight, and the document that matters
describes what is deployed. Two paths are declared in `manifest.env`: the human
page, `/docs` by default, and the JSON document, `/docs/json` by default. The
harness fetches the JSON and confirms that it is an OpenAPI document describing
the four routes. It does not replace `contracts/auth-api.yaml`. It is the
evidence that your code still matches it.

## The security review

The deliverable is a committed file, not a conversation at the review. Copy
`security-review/TEMPLATE.md` to a file of your own in the same folder, name it
in `manifest.env`, and fill it in as you build. The categories are the OWASP Top
Ten items that bear on an authentication service, and the template says where to
look for each of them.

Every category carries a finding and a disposition, both written. A finding of
"none" needs a sentence naming what you checked, because "none" with nothing
beside it is indistinguishable from a category nobody looked at. A disposition of
"accepted" needs the residual risk and why the team is carrying it. If you did
not build revocation of the presented refresh token, A04 is where that decision
and its risk are written. The harness checks that the cells are filled. Whether
what is in them is true is read by your instructor.

## Acceptance criteria

These are the criteria your instructor assesses against.

1. All four endpoints are implemented and match the contract, including the
   error envelope and every code in it.
2. The access token carries exactly the claims contract: `sub`, `accountId`,
   `roles`, `iat`, `exp`, and the `iss` the contract also defines.
3. Swapping the stub for this service is a configuration change only, with no
   code change in the Trade REST API.
4. Passwords are hashed with argon2 or bcrypt, and never logged.
5. Every refresh issues a new refresh token. Revoking the token that was
   presented is optional, and where it is not built the decision and the risk it
   accepts are written in the security review.
6. A failed login returns the same response, and comparable timing, for an
   unknown user as for a wrong password.
7. Jest tests cover the guard, including the expired-token and wrong-signature
   paths.
8. The running service serves its OpenAPI document.
9. The security review against the auth-related OWASP items is committed, with a
   finding and a disposition for every category.

## The check harness

`scripts/check.sh` asserts the things a machine can assert, in two modes.
**Static mode** is the default: no container, no database, no running service.

| Check | What it proves |
|---|---|
| `npm ci` installs from the lock file | A teammate gets the tree you tested, rather than whatever resolves the day they clone it |
| `npm run build` succeeds from a clean state | The service compiles from the files in the repository |
| The Jest suite runs and is green | Criterion 7, the existence half |
| A spec covering the guard ran, with a passing test for the expired-token path and one for the wrong-signature path | Criterion 7 |
| No log call in your sources names a credential field | Criterion 4, the never-logged half, in its direct form |
| The security review exists, differs from the template, and every category carries a finding and a disposition | Criterion 9 |

**Live mode**, `scripts/check.sh --live`, adds the probes. It needs your stack
up: your service running against its store, and your Sprint 6 service running
and pointed at it.

| Probe | What it proves |
|---|---|
| Register, login, refresh and `/auth/me` against the contract | Criterion 1 |
| A decoded access token, claim by claim | Criterion 2 |
| A wrong password and an unknown user, compared on status, body and elapsed time | Criterion 6 |
| One refresh, the token it returned, and then whatever `ROTATION_REVOCATION` declares | Criterion 5 |
| The stored password hash, where your manifest tells the harness how to read it | Criterion 4, the algorithm half |
| A protected Trade REST API route with a token from this service, and with a token signed by a key it should not trust | Criterion 3, behaviourally |
| The OpenAPI document, fetched from the running service | Criterion 8 |

Criterion 5 is the one probe that reads a declaration rather than fixing the
behaviour. Set `ROTATION_REVOCATION=enforced` and the harness presents the
exchanged refresh token again and requires `AUTH-401`. Set it to `documented`
and that probe is replaced by a check that your security review carries the
decision in writing, with the harness printing what it would have probed on the
stricter setting. Both settings assert that a refresh returns a new refresh
token and that the new one works.

Criterion 3 is read with `git diff` at the design review, and the harness prints
the command: no script can tell a configuration change from a code change that
looks like one. Everything else it needs comes from `manifest.env`, so it
asserts your design rather than dictating one.

Passing is necessary and not sufficient. The harness reads structure and
behaviour at the edges, and cannot see whether a password reaches a log by an
indirect route, whether the cost factors were chosen against anything, whether
the refresh decision your manifest declares is one the team reasoned about, or
whether the uniform failure holds because both paths do the same work rather
than because the machine was quiet. All four are read at the review.

Bring to it: the running stack with the stub removed, one token decoded
in front of the panel, your refresh traced through your store, the `git diff`
showing no Java changed, and your answer to what you would do at 09:00 on the
morning somebody reports a stolen refresh token.

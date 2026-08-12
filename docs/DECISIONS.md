# Decisions

Audience: instructors and material authors. These decisions are agreed with the programme owner and are binding. They override the project specification document (`Enterprise_Trading_Platform_Project.docx`) and the curriculum deck (`Neueda_Leap_Program_Detailed_Curriculum_v2.pptx`) wherever the three disagree. Do not reopen them in week material. If a participant asks why the source deck says something different, the answer is in this file.

Each entry states the decision, why it was taken, and what it changes in the build.

---

## 1. No Broker Simulator API. Participants build the Trade Executor and the fill logic.

**Decision.** The Broker Simulator API described in the specification (sections 5, 10.1, 15 FR-12) does not exist and will not be provided. In Sprint 7 participants build the Trade Executor themselves: a Kafka consumer that reads the `orders` topic, fetches a live price from the Fauxnance API, applies fill or reject rules, writes the resulting state change to Postgres in one transaction, and publishes the outcome to `trade-events`.

**Why.** Calling a provided simulator teaches HTTP client code that participants already wrote in Sprint 6. Writing the executor teaches the thing Sprint 7 is actually assessed on: consumer groups, offsets, idempotent processing, and what "at-least-once" costs you when the side effect is money. It also gives the sprint a genuine failure mode to reason about, because a duplicate delivery that double-debits an account is a real bug they can produce and then fix. Building a simulator would additionally have meant standing up and supporting another hosted service for the whole cohort.

**What changes.** FR-12 now reads: execute trades asynchronously in the Trade Executor against live prices from the Fauxnance API. The specification's Execution layer row loses its external dependency. Fill rules are the participants' design decision, constrained by the business rules in section 20 and by the acceptance criteria in `CURRICULUM_MAP.md`. A workable default is: fill the whole order at the current quoted price if a BUY limit price is at or above the quote, or a SELL limit price is at or below it; reject otherwise. Partial fills are out of scope, because the order status enumeration has no state for them.

---

## 2. The Live Pricing API is Fauxnance, already deployed, and it has no stream.

**Decision.** Market data comes from the Fauxnance API at `https://y4t9nq2bqf.execute-api.eu-west-2.amazonaws.com/v1`. Each participant receives a personal key, sent in the `X-Api-Key` header, with a quota of 2000 requests per day.

Endpoints in scope for the capstone:

| Endpoint | Use |
|---|---|
| `GET /candles/{symbol}` | Historical end-of-day OHLCV. Sprint 4 analytics, Sprint 10 signals and strategies. |
| `GET /quotes/{symbol}` | One delayed quote. The Trade Executor prices a fill with this. |
| `GET /quotes?symbols=A,B,C` | Batch quotes, maximum 25 symbols, counts as one request against quota. Portfolio valuation and the poller use this. |
| `GET /usage` | The caller's own quota status. Use it when a team reports mysterious 429s. |
| `GET /health` | No key required. Use it to rule out "is it the API or is it me". |

Swagger UI is at `/v1/docs`.

**Why.** The service already exists, is stable, and covers both US and Indian symbols (`INFY.NS`, `RELIANCE.NS`, `TATASTEEL.BO`) as well as FX and crypto, so both cohorts can trade instruments they recognise. Building a second pricing service for the programme would duplicate it.

**What changes.** Fauxnance serves end-of-day candles and delayed quotes. There is no WebSocket and no server-sent events. The "real-time price stream" the deck refers to therefore does not arrive by itself. In Sprint 7, participants write a small poller that calls the batch quotes endpoint on an interval and publishes each quote onto the `market-data` topic. That poller is what creates the stream, and its existence is the reason Sprint 10 extensions such as Watchlists and Automated Strategy Execution have anything to consume.

The 2000-per-day quota constrains design and is meant to. Teams that poll every symbol every second exhaust a key before lunch. Correct behaviour is to poll only held and watched symbols, to batch up to 25 symbols per call, and to cache. Instructors should let a team hit the limit once rather than warn them out of it.

Two operational rules are non-negotiable. Keys live in environment variables, never in the repository. The Angular UI never calls Fauxnance, because doing so would ship a key to the browser.

---

## 3. Six extensions, with different mandatory sets per cohort.

**Decision.** The extension catalogue has six entries:

1. Portfolio and P&L
2. Trade Advice and Signals
3. Watchlists and Price Alerts
4. Customer Notifications
5. Customer Preferences and Personalisation
6. Automated Strategy Execution

**US and Ireland (12 weeks, Sprint 10):** exactly one extension is mandatory. The team chooses which.

**India (9 weeks, Sprint 10):** all six are recommended. Four are mandatory:

- Portfolio and P&L
- Watchlists and Price Alerts
- Customer Preferences and Personalisation
- Customer Notifications

**Why.** The US and Ireland run spends a full applied-project week on one extension and is assessed on depth, integration quality and the security review. The India cohort are returning interns who already hold the fundamentals, start at applied depth, and have a shorter run with less taught time per topic; four narrower extensions give them more integration surface and more visible product value in the same calendar space. The four chosen for India form one coherent customer-facing feature set rather than four unrelated services.

**Dependencies, which drive build order.** Customer Notifications depends on Customer Preferences, because a notification cannot be routed without a channel preference. Watchlists alerting depends on Notifications, because a triggered threshold has to be delivered somewhere. India teams therefore build in the order Preferences, Notifications, Watchlists, with Portfolio and P&L independent of the other three and safe to build in parallel.

A team that ships Watchlists with alerts written only to a log has not met the criterion. The alert must reach the Notifications service, which must respect the customer's stored channel preference.

---

## 4. The deck's technology stack table is wrong. This is the correct scope.

**Decision.** Ignore the "Technology Stack by Sprint" slide. The following do not appear anywhere in the programme: Selenium, Apache ActiveMQ, Jenkins, JFrog, Amazon EKS, Amazon RDS, VPC configuration, Elastic Load Balancing, Secrets Manager, Certificate Manager, CloudWatch.

The correct scope:

| Area | In scope |
|---|---|
| AWS | IAM, AWS CLI, S3, CloudFront. Nothing else, and only in Sprint 11. |
| Messaging | Apache Kafka only. |
| End-to-end testing | Playwright, Sprint 9. |
| Unit testing | JUnit 5 for Java, Jest for TypeScript, pytest for Python. |
| CI | None. Checks and deployment run as scripts. |
| Quality | SonarQube, Sprint 7. |
| Containers | Docker and Docker Compose, from Sprint 6. |

**Why.** The slide was assembled from a generic enterprise stack list and does not match the taught content, the assessments, or the deployment target. Selenium contradicts the Sprint 9 material, which teaches Playwright. ActiveMQ appears in a sprint whose learning outcomes are entirely Kafka. The Sprint 11 row lists a managed-Kubernetes deployment stack for a sprint that deploys a static Angular build to object storage behind a CDN. Leaving the errors in place would send participants to install tooling the programme never uses, and would make the AWS week look far larger than the four and a half days allocated to it.

**What changes.** Material authors must not reference the removed technologies, including as "awareness only" asides. If a Fidelity platform SME session covers Fidelity's own AWS estate, that is a briefing, not a lab, and no participant deploys to it.

---

## 5. Sprint 6 authenticates against a provided Node auth stub.

**Decision.** A minimal Node authentication stub is shipped in the starter material. It exposes the same routes as the eventual NestJS service and issues JWTs with an identical claims contract: `sub`, `accountId`, `roles`, `iat`, `exp`, signed with the same algorithm and a shared development secret. Participants integrate the Trade REST API against it in Sprint 6 and keep using it through Sprint 7. In Sprint 8 they build the real service and swap it in.

**Why.** Sprint 6 teaches JWT validation in Spring Boot and requires a protected route to demonstrate it. Node and NestJS are not taught until Sprint 8. Without a stub, participants would either hard-code a token, which teaches nothing about verification, or disable security for two sprints and retrofit it, which is exactly the habit the programme is trying to break. The stub is provided rather than built because writing it would mean teaching Node two sprints early.

**What changes.** The stub is a fixture, not a deliverable. It has no tests to write, no bugs planted in it and no assessment attached. Its claims contract is normative: `contracts/auth-api.yaml` describes both the stub and the Sprint 8 service, and the Sprint 8 acceptance criterion is that swapping one for the other requires no change to the Trade REST API beyond configuration. Both listen on port 3000 for that reason.

The stub's issuer name is `auth-stub` rather than `auth-service`, so that a team can prove which one signed a token during the Sprint 8 cutover.

---

## 6. Deliberately imperfect starter code applies to the us-ireland branch only.

**Decision.** The planted-defect starter codebase, meaning the basic Trade and Portfolio API stubs carrying intentional bugs, security vulnerabilities and legacy patterns, exists on the `us-ireland` branch only. The `india` branch starts from clean stubs. A defect catalogue is maintained for instructors, listing every planted issue, its OWASP category where relevant, the sprint at which it is expected to surface, and the accepted remediation.

**Why.** The imperfect-codebase premise costs time: participants must read code before writing any, and the Sprint 7 refactoring and characterisation-test work depends on there being something worth refactoring. The India run is three weeks shorter, starts at Sprint 3, and covers the same nine capstone components. Something had to give, and reading someone else's broken code is the part these participants have already done, since they are returning interns who worked in the codebase during their internship.

**What changes.** The Sprint 7 refactoring mission differs by branch. On `us-ireland` teams write characterisation tests around the planted starter code and refactor it. On `india` teams write characterisation tests around their own Sprint 6 code before extending it, which delivers the same learning outcome against a different subject. Assessment rubrics for Sprint 7 must be phrased against the outcome, not against the specific defects.

The defect catalogue is instructor-only material. Do not commit it to either student branch.

---

## Resolved contradictions in the source documents

These are not new decisions. They record where the sources disagreed with themselves and what the reference implementation does.

| Contradiction | Resolution |
|---|---|
| `Account.id` is a `Long` surrogate key while `Account.accountId` is a `String` business identifier (17.1), but `Order.accountId` is a `Long` (17.2) and the API example sends `"accountId": 1` (19.1). | The name `accountId` means the numeric `ACCOUNTS.id` everywhere in the API, in `ORDERS`, in `POSITIONS` and in the JWT `accountId` claim. The string business identifier appears only as `ACCOUNTS.account_id` and in `AccountResponse.accountId`, where it is documented as such. The reference DDL keeps both columns exactly as specified, with a comment on the collision. |
| `POST /api/v1/orders` returns `"status": "FILLED"` (19.1), but Sprint 7 makes execution asynchronous. | Both are correct at different points in the build. Sprint 6 fills synchronously and returns `FILLED` or `REJECTED`. From Sprint 7 the endpoint returns `NEW` and the fill arrives on `trade-events`. The contract documents both and the UI must handle both. |
| A basic Portfolio REST API is described as provided in Sprint 6, and Portfolio and P&L is also an optional Sprint 10 extension. | Sprint 6 exposes balance and positions on the account endpoints of the Trade REST API, as specified in 19.2. There is no separate Sprint 6 Portfolio service. The Sprint 10 extension is a distinct service that adds market valuation, cost basis and profit and loss. |
| The topic carrying new orders is named `trades` (10.3) while the messages on it are placed orders. | The canonical name is `orders`. `trades` is accepted where a team has already built against it, but a repository must use one name consistently. |
| The lenses slide places TDD in Sprint 6, characterisation tests and SonarQube in Sprint 5, and DevSecOps in Sprint 5. The detailed weekly schedules place TDD in Sprint 5, and refactoring, SonarQube and DevSecOps in Sprint 7. | The detailed weekly schedules are correct. The lenses slide is off by one or two sprints throughout. |
| Sprint 8 material refers to "the Sprint 7 stub". | The auth stub is introduced in Sprint 6 and used through Sprint 7. See decision 5. |
| The Sprint 6 capstone cell in the weekly plan reads "team microservice choice documented; service scaffolded". | Boilerplate carried over from another template. The Sprint 6 deliverable is the Trade REST API. Extension choice is confirmed in Sprint 10. |
| Analytics is specified as Snowflake, while the Sprint 7 lab offers "Snowflake overview or flat file". | Either is acceptable in delivery. `contracts/analytics-schema.sql` is plain ANSI SQL and runs on Snowflake, DuckDB or SQLite. Teams without a Snowflake account use DuckDB. |
| The India weekly cadence dates Week 8 as commencing 5 October and marks its Friday as Gandhi Jayanti, which falls on 2 October. | The holiday markers in `CURRICULUM_MAP.md` follow the programme owner's instruction: Monday of India week 6 and Friday of India week 8. Confirm the calendar dates with the delivery team before publishing a dated schedule. |
| The programme is described as 11 weeks in the outcomes slides and runs across 12 calendar weeks in the schedule. | Twelve calendar weeks for US and Ireland: an induction week plus eleven sprints. Capstone components run in Sprints 3 to 11, which are calendar weeks 4 to 12. |

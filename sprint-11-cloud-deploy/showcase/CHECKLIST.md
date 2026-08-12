# Showcase checklist

Fill this in during the week and commit it. The panel reads it before you start,
and it is the file your team argues over while there is still time for the
argument to change something.

Replace every `TODO`. A row you leave as `TODO` is a decision you have chosen to
take live, in front of the panel, with a clock running.

| Field | Value |
|---|---|
| Team | TODO |
| Extension built in Sprint 10 | TODO |
| Deployed URL | TODO |
| Slot length confirmed with the instructor | TODO |
| Date and time of the rehearsal run | TODO |

## Before the room

Tick these on the morning, in this order. Every one of them has been the reason a
demonstration failed for a previous cohort.

| Check | Done by | Status |
|---|---|---|
| Stack up: Postgres, Kafka, Trade REST API, Auth service, Trade Executor, poller, extension | TODO | TODO |
| The deployed URL loads, in a private window, on a machine that is not the one that deployed it | TODO | TODO |
| Sign-in works from the deployed URL with the demo user | TODO | TODO |
| Fauxnance quota checked, with headroom for the demonstration | TODO | TODO |
| A tradable symbol seeded and priced, ready for the order you will place | TODO | TODO |
| Screen resolution and font size set so the back row can read the terminal | TODO | TODO |
| Notifications, chat and email quietened on the presenting machine | TODO | TODO |
| The fallback material below open in tabs, not bookmarked | TODO | TODO |

## Demo order

Fix the order now, so nobody is deciding what comes next while presenting. The
proportions to aim for are roughly half the slot on the live platform, a quarter
on decisions and quality, and the rest for questions.

| # | Segment | Who presents | Minutes | What is on screen |
|---|---|---|---|---|
| 1 | The platform in one sentence, and the deployed link opened live | TODO | TODO | The deployed URL |
| 2 | Sign in, place an order, watch it fill and reach the blotter | TODO | TODO | The application, then the executor logs |
| 3 | What happened behind that: the API, the topic, the executor, the database | TODO | TODO | TODO |
| 4 | The analytical side: the pipeline and the insights it answers | TODO | TODO | TODO |
| 5 | The extension, running on live data | TODO | TODO | TODO |
| 6 | The deployment: the entry point, and what one run does | TODO | TODO | The script, and a run |
| 7 | Design decisions: two or three, with what was rejected | TODO | TODO | The decision log |
| 8 | Copilot: where it helped, where it was wrong, how you knew | TODO | TODO | TODO |
| 9 | The code-quality story: the gate, the reviews, the tests | TODO | TODO | The SonarQube project |
| 10 | Questions | Everyone | TODO | Nothing |

## Who covers which component

Every member presents a segment above, and any member may be asked about any
component below. Name an owner for each so that questions have somewhere to go
first, then rehearse with the owners swapped.

| Component | First answer | Second answer |
|---|---|---|
| Trade database schema and seed | TODO | TODO |
| Analytics pipeline and dashboard | TODO | TODO |
| Domain engine and the trading rules | TODO | TODO |
| Trade REST API | TODO | TODO |
| Kafka topics, Trade Executor and the poller | TODO | TODO |
| Auth service and the token contract | TODO | TODO |
| Angular application | TODO | TODO |
| The extension | TODO | TODO |
| The deployment, the bucket and the distribution | TODO | TODO |
| Security reviews and the quality gate | TODO | TODO |

## If live data misbehaves

Live data is a criterion, so the fallback is not a substitute for it. The
fallback exists so that a bad quote or a dead container costs you thirty seconds
rather than the segment. Agree who calls it and what happens next.

| If this happens | Then | Agreed by |
|---|---|---|
| The market-data quota is exhausted | TODO | TODO |
| A quote comes back stale or the market is closed | TODO | TODO |
| The order sits at `NEW` and does not fill | TODO | TODO |
| A container is down and will not come back quickly | TODO | TODO |
| The deployed URL serves a stale build | TODO | TODO |
| The deployed URL does not answer at all | TODO | TODO |
| Sign-in fails from the deployed URL | TODO | TODO |

Two rules on fallbacks. The person presenting does not debug: somebody else takes
the keyboard while the segment continues. And say what you are doing rather than
narrating silence, because a team that names the problem and moves on reads as a
team that has seen one before.

## Evidence links

The panel follows these rather than taking your word for any of it. Give a link
or a path for each, and check every one resolves on the morning.

| Evidence | Where |
|---|---|
| Deployed application | TODO |
| Repository | TODO |
| Deployment entry point (script) | TODO |
| Most recent deploy run | TODO |
| SonarQube project and its latest gate result | TODO |
| Decision log | TODO |
| Sprint 8 security review | TODO |
| Sprint 10 security review, with findings and their dispositions | TODO |
| Test suites and how they are run | TODO |
| Backlog or board for Sprint 10 and Sprint 11 | TODO |

## Teardown

Not part of the demonstration, and it is on this checklist so that it is not
forgotten once the room empties.

| Step | Done by | Status |
|---|---|---|
| Date teardown was instructed for | TODO | TODO |
| Bucket emptied and deleted | TODO | TODO |
| Distribution disabled, then deleted | TODO | TODO |
| Origin access control removed | TODO | TODO |
| Deploy user, its policy and its access keys removed | TODO | TODO |
| Deploy secrets removed from the repository settings | TODO | TODO |

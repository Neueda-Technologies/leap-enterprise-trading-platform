# Sprint 10: the extension service

For seven sprints the work has been specified for you. A contract said what the
Trade REST API returned, `kafka-topics.md` said what the envelope looked like, a
brief said which eight business rules the domain engine enforced, and the
acceptance criteria said when you were finished. That was deliberate: a platform
built by four teams to four different designs cannot be assessed against itself,
and the fastest way to teach a convention is to hand it over and make people
build to it.

This week nothing is handed over. You choose a feature, decide what it is worth
building in five days, design its API, agree its integration surface, build it,
secure it, and demonstrate it against a running platform. The technology is
technology you already have. What is new is that the decisions are yours, and
that the way you took them is part of what is assessed.

That is why the folder is thin. There is no scaffold in here, because there is
nothing to scaffold until you have chosen. What is here is the catalogue, the
shape of the two documents you have to produce, and a harness that checks the
handful of things a script can check.

## What changes this week

No new technology is taught. Every tool this sprint needs, you have used: Java or
Node for the service, Kafka for the events, Postgres for the state, Docker for
the packaging, Angular for the screen, SonarQube for the quality gate, JUnit or
Jest for the tests.

You run the sprint. Plan it, split it, track it, review each other's pull
requests, and hold whatever ceremonies your team has settled into. Instructors
are available all week and will not be assigning work.

Process is assessed alongside product. A team that ships a working service with
no backlog, no decision log and a security review written on the Thursday
evening scores below a team that ships something narrower and can show how it
was decided. The two documents in this folder are not paperwork attached to the
build; they are half of the deliverable.

## Day one

Three things happen before any code is written, and they happen on the Monday.

**Choose the extension.** One from the catalogue below. Six briefs, one file
each, and they are written to be picked between rather than ranked. Read all six
before arguing about any of them.

**Confirm the scope with an instructor.** Bring what you intend to build by
Friday, what you have decided not to build, and the API you propose to expose.
For five of the six extensions the API design is yours, and this is the review it
gets. For Portfolio and P&L the contract is already written and the conversation
is about everything around it. Scope confirmed on day one is an acceptance
criterion, not a courtesy.

**Write the backlog before you write code.** Stories with acceptance criteria, in
whatever tracker your team has been using. A backlog assembled on Friday morning
from the commits is visible as one, and it is worth less to you than to anybody
marking it: the point of writing it first is that it tells you on Wednesday
whether the scope you agreed is still the scope you are building.

## The catalogue

| Extension | Identifier | Brief | Integrates through |
|---|---|---|---|
| Portfolio and P&L | `portfolio-pnl` | [catalogue/portfolio-pnl.md](catalogue/portfolio-pnl.md) | Postgres, Fauxnance quotes, optionally `trade-events` and `market-data` |
| Trade advice and signals | `trade-advice-signals` | [catalogue/trade-advice-signals.md](catalogue/trade-advice-signals.md) | `market-data`, Fauxnance candles, optionally `trade-events` |
| Watchlists and price alerts | `watchlists-price-alerts` | [catalogue/watchlists-price-alerts.md](catalogue/watchlists-price-alerts.md) | `market-data`, and a delivery route to the customer |
| Customer notifications | `customer-notifications` | [catalogue/customer-notifications.md](catalogue/customer-notifications.md) | `trade-events`, and an outbound channel |
| Customer preferences and personalisation | `customer-preferences` | [catalogue/customer-preferences.md](catalogue/customer-preferences.md) | The Angular application and other services, over HTTP |
| Automated strategy execution | `automated-strategy-execution` | [catalogue/automated-strategy-execution.md](catalogue/automated-strategy-execution.md) | `market-data`, `trade-events`, and `POST /api/v1/orders` |

The identifier is what you declare in `manifest.env`. It is also the folder name
to use for the service itself, under `services/`.

One extension is the deliverable. The assessment is depth, integration quality
and the security review for that one service, so a narrow extension built
properly is worth more than a wide one built thinly. Two half-built extensions
are worth less than either of them finished.

## What every extension has to do

The feature is your choice. Four properties are not, and they are the same four
whichever brief you pick.

**It is a separate service.** Its own port, its own folder under `services/`, its
own entry in `docker-compose.yml`, its own Dockerfile, its own README covering
configuration, how to run it and what its tests do and do not cover. Not a
package inside the Trade REST API.

**It authenticates with the platform JWT and authorises on its own routes.** The
service verifies the signature itself, on every request, with the same claims
contract as `contracts/auth-api.yaml`. It does not trust that something upstream
already checked. Verification is not authorisation: after the token is verified,
the service compares the `accountId` claim against the resource being addressed
and refuses a mismatch. A route that returns another customer's data to a valid
token is the finding this sprint's security review exists to catch.

**It integrates with Kafka or the Trade REST API, and it is reachable from the
Angular UI.** Consuming a topic, producing to one, or calling the Trade REST API
all count. A service that only talks to its own database has not been integrated
into the platform. Reachable from the UI means a screen in the Sprint 9
application that a customer can use, generating its client from your OpenAPI
document the way the other clients are generated. A route that answers only to
`curl` does not meet the criterion.

**It runs on live data at the demonstration.** Real quotes from the Fauxnance
API, real messages from the topics your poller and executor are producing, real
rows from your Postgres. Not fixtures, not a seeded response, not a recorded
payload replayed from a file. Fixtures belong in the test suite, and a
demonstration that runs on them is demonstrating the fixture.

Two platform rules carry over unchanged. The Fauxnance key is read from the
environment and never reaches the browser. Every consumer sets an explicit
`group.id`, listed in your service README, and does not share it with another
service.

## The decision log

Committed in `decision-log/`, one file per decision, using the shape in
[decision-log/TEMPLATE.md](decision-log/TEMPLATE.md). It is an acceptance
criterion for this sprint and it is read at the final showcase in Sprint 11.

Write entries as you take the decisions. A log assembled in the last hour of the
sprint records what you built, which everyone can already see, and loses the
thing that makes it worth reading: what you nearly did instead, and why you did
not. It also reads exactly like what it is.

An entry is worth writing when reversing the choice later would cost more than an
afternoon, when a competent engineer would have chosen the other option, or when
somebody on the team asked why and the answer took a paragraph. Four to six
entries is a normal week. Twenty is a changelog and one is not a log.

### A worked entry

Neutral subject, so that the shape is visible without the content doing the work
for you.

````markdown
# 0003 One consumer group for the service, sized to the partition count

| Field | Value |
|---|---|
| Status | accepted |
| Date | 2026-11-17 |
| Decided by | the whole team, at the Tuesday stand-up |

## Context

The service consumes `market-data`, which `contracts/kafka-topics.md` fixes at
six partitions because it carries the highest message rate on the platform. We
intend to run more than one instance of the service in Docker Compose so that we
can show what happens when one is killed. Kafka assigns partitions to consumers
within a group, so how we set `group.id` decides whether a second instance shares
the work or duplicates it.

## Options considered

| Option | For | Against |
|---|---|---|
| One group for the service, one consumer per instance | Partitions are split across instances, so work is shared and a lost instance is rebalanced onto the others | Only useful up to six instances, since a consumer beyond the partition count is idle |
| A group per instance | Every instance sees every message, which is simple to reason about | Every instance does the same work, and every alert would be evaluated and delivered as many times as we have instances |
| One consumer, no scaling | Nothing to configure | A single point of failure, and no way to demonstrate a rebalance |

## Decision

One group, `watchlist-service`, with each instance running one consumer, and no
more than six instances. The second option is not a scaling design at all: with
this service the duplicate work is a duplicate customer notification, which is a
defect a customer sees rather than wasted CPU.

## Consequences

Scaling past six instances buys nothing, and we have written that in the service
README next to the compose entry. A rebalance pauses consumption briefly when an
instance joins or leaves, so the alert evaluation has to be idempotent on
`eventId` anyway, which we were going to need for at-least-once delivery. The
group identifier is now part of our operational surface: another service adopting
the same name would silently take half our messages, which is why it is listed in
the README.
````

What makes that entry useful is not its length. It states what was true when the
decision was taken, gives an option that was genuinely considered and rejected,
names the thing that decided it, and admits a cost. An entry with one option in
it is a record of what you did.

## The security review

An OWASP review of the new service, committed in this folder, using the shape of
the template from Sprint 8 at
`../sprint-08-auth-service/security-review/TEMPLATE.md`. Copy it, retitle it for
your service, and name your copy in `manifest.env`.

Two things change from Sprint 8. The categories are the ones that bear on your
service rather than on an authentication service, and the default set in
`manifest.env` is the full Top Ten, because an extension that consumes events,
calls a third party and serves a customer touches more of the list than the Auth
service did. A category that genuinely does not apply is dispositioned as out of
scope with the reason, not deleted: a category with nothing in it is the one
worth asking about.

The second change is that findings have to be addressed. The criterion is not a
review that exists, it is a review whose findings were dealt with. Fixed, with
the commit. Mitigated, with what limits the exposure. Accepted, with the residual
risk stated and named as a decision the team took. A finding still open on Friday
belongs in the outstanding items table with an owner against it, and it will be
asked about.

Start with the access-control row. Every brief in the catalogue names the same
first risk, because every one of these services holds data belonging to one
customer and reachable with a token belonging to another.

## The quality gate

SonarQube passing on the new service, on the same terms as Sprint 7. Run it
during the week rather than on Friday: a gate run once, at the end, against a
week of code produces a list nobody has time to act on, which is how a quality
gate turns into a formality.

The harness does not run Sonar and cannot see the result. Bring the gate result
to the review, with the analysis date and the project key, and be ready to talk
about anything you marked as won't fix.

## What is in this folder

```
README.md              this brief
catalogue/             six briefs, one per extension
decision-log/          TEMPLATE.md, and your entries beside it
manifest.env           the names the harness reads
scripts/check.sh       the acceptance harness
```

Your service does not live here. It lives in `services/<identifier>/` with the
rest of the platform, and it goes into `docker-compose.yml` like everything else
you have built. This folder holds the sprint's documents and the harness that
reads them.

Your security review goes in this folder. The default name in `manifest.env` is
`security-review/REVIEW.md`.

## The harness

`scripts/check.sh` runs in two modes. It is deliberately lighter than the
harnesses in earlier sprints, because there is no contract for it to assert
against for five of the six extensions and no scaffold for it to know the shape
of.

Static mode, with no arguments, reads `manifest.env` and confirms that your
declared extension is one of the six, that the decision log holds enough entries
that are not the template, and that the security review exists, is not the
template, and carries a finding and a disposition in every category. It then
prints a note about the SonarQube gate, which it cannot check.

```bash
scripts/check.sh
scripts/check.sh --live
```

Live mode needs your stack up: the service, the Auth service, and whatever your
extension consumes. It starts nothing and stops nothing. It confirms the health
endpoint answers, then puts three requests to a protected route: one with no
token, one with a token that is well formed and signed with a key nobody holds,
and one with a real token from your Auth service. The first two are refused, the
third succeeds. If you declared `portfolio-pnl`, it also reads the two main
routes from `contracts/portfolio-api.yaml` and checks the response shape against
the contract.

Every skip is named and explained. A skip is honest. A green run against
something that was not there is not.

## Acceptance criteria

These are the criteria your instructor assesses against.

1. The extension is chosen and its scope is confirmed with an instructor on day
   one.
2. The service authenticates with the platform JWT and enforces authorisation on
   its own routes.
3. It is integrated with at least one of Kafka or the Trade REST API, and it is
   reachable from the Angular application.
4. An OWASP security review of the new service is completed and its findings are
   addressed.
5. The SonarQube quality gate passes.
6. An architecture decision log is committed, giving the reasoning for each
   significant choice.
7. The team can demonstrate the feature working against live data, not fixtures.

## Most of this week is assessed by a human

Say it plainly, because the harness is short enough that a team could mistake a
green run for a finished sprint. The harness checks that four files exist and say
something, and that three HTTP requests get the answers they should. That is all
it can check.

Everything the criteria actually turn on is read by a person: whether the scope
you agreed on Monday is the scope you delivered, whether the decision log records
decisions or events, whether the security review is a reading of your service or
of the template, whether the findings were addressed or restated, whether the
authorisation check still refuses a second customer's token, whether the screen
in the Angular application is usable, and whether the data at the demonstration
was live.

Every member of the team is expected to walk the extension unaided at the
showcase, including the parts they did not write.

# Sprint 10: the extension services

For seven sprints the work was specified for you. A contract said what the Trade REST API
returned, `contracts/kafka-topics.md` said what an envelope looked like, a brief said which
business rules the domain engine enforced, and the acceptance criteria said when you were
finished. That was deliberate. A platform built by four teams to four different designs cannot
be assessed against itself, and the fastest way to teach a convention is to hand it over and
make people build to it.

This week the platform is finished and nobody is handing you a design. Four services are named
and their behaviour is fixed by the acceptance criteria, and everything between those two
things is yours: the APIs, the schemas, the order the work is taken in, who does what, and how
you know on Wednesday whether Friday is reachable. The technology is technology you already
have. What is new is that the decisions are yours, and that the way you took them is part of
what is assessed.

That is why this folder is thin. There is no scaffold in here, because there is nothing to
scaffold until you have designed it. What is here is the four briefs, the shape of the two
documents you have to produce, and a harness that checks the handful of things a script can
check.

## What changes this week

No new technology is taught. Every tool this sprint needs, you have used: Java or Node for the
services, Kafka for the events, Postgres for the state, Docker for the packaging, Angular for
the screens, JUnit or Jest for the tests.

You run the sprint. Plan it, split it, track it, review each other's pull requests, and hold
whatever ceremonies your team has settled into. Instructors are available all week and will not
be assigning work.

Process is assessed alongside product. A team that ships four running services with no backlog,
no decision log and a security review written on the Thursday evening scores below a team that
ships less and can show how it was decided. The two documents in this folder are not paperwork
attached to the build. They are half of the deliverable.

This is also the last sprint in which the platform is assessed. The cloud week that follows is
assessed on the deployment, so the demonstration of the platform itself happens at the end of
this one, against a running stack.

## Four services, and why the order is fixed

All four are mandatory. They are not four unrelated services either: three of them form one
chain, and the chain is the reason the build order is not a matter of taste.

| Order | Extension | Brief | Depends on |
|---|---|---|---|
| 1 | Customer preferences | [catalogue/customer-preferences.md](catalogue/customer-preferences.md) | Nothing in this list |
| 2 | Customer notifications | [catalogue/customer-notifications.md](catalogue/customer-notifications.md) | Preferences, for the channel |
| 3 | Watchlists and price alerts | [catalogue/watchlists-price-alerts.md](catalogue/watchlists-price-alerts.md) | Notifications, for delivery |
| 4 | Portfolio and P&L | [catalogue/portfolio-pnl.md](catalogue/portfolio-pnl.md) | Nothing in this list |

Read the chain in one sentence. Preferences owns the customer's alert channel and hands it to
notifications; notifications consumes `trade-events` and delivers on that channel, and is also
the delivery path watchlists uses; watchlists consumes `market-data`, decides that a threshold
has been crossed, and asks notifications to tell the customer.

Each link is a hard dependency rather than a preference. A notification cannot be routed
without a channel, so notifications built before preferences either hardcodes a channel or
waits. An alert has to arrive somewhere, so watchlists built before notifications either writes
to a log, which does not meet the criterion, or waits. Build them in order and each service
finds its dependency already there.

Portfolio and P&L sits outside the chain. It depends on none of the other three and none of
them depend on it, so it can be built at any point in the week and by anyone. It has its own
external dependencies instead: `contracts/portfolio-api.yaml`, which binds it the way
`trade-api.yaml` bound Sprint 6, the Fauxnance API for prices, and the platform APIs and tables
it reads. That combination makes it the one service in the four with the least design freedom
and the most failure modes, which is worth knowing when you decide who takes it.

The dependency order is the build order and it is not the assignment order. Four people
starting four services on Monday morning produces three of them blocked by lunchtime.

## Day one

Three things happen before any code is written, and they happen on the Monday.

**Read all four briefs, as a team.** Every one of you, all four. The chain means a decision
taken inside preferences on Monday becomes notifications' problem on Tuesday and watchlists'
problem on Wednesday, and the people who will hit that need to have read the brief it came
from.

**Confirm the scope with an instructor.** Bring what you intend to build by Friday, what you
have decided not to build, and the APIs you propose to expose for the three services that have
no contract. Bring the shape of the integration between them: how notifications asks
preferences for a channel, and how watchlists asks notifications to deliver. Scope confirmed on
day one is an acceptance criterion, not a courtesy.

**Write the backlog for all four before you write code.** Stories with acceptance criteria, in
whatever tracker your team has been using, covering every one of the four rather than the one
somebody started first. A backlog assembled on Friday morning from the commits is visible as
one, and it is worth less to you than to anybody marking it. Writing it first is what tells you
on Wednesday whether the scope you agreed is still the scope you are building, which is the
week's real risk with four services in it.

## What all four have to do

The features differ. Four properties do not.

**Each one is a separate service.** Its own port, its own folder under `services/`, its own
entry in `docker-compose.yml`, its own Dockerfile, its own README covering configuration, how
to run it and what its tests do and do not cover. Four services, not one service with four
packages in it and not three services and a module.

**Each one authenticates with the platform JWT and authorises on its own routes.** Every
service verifies the signature itself, on every request, with the same claims contract as
`contracts/auth-api.yaml`. None of them trusts that something upstream already checked.
Verification is not authorisation: after the token is verified, the service compares the
`accountId` claim against the resource being addressed and refuses a mismatch. A route that
returns another customer's preferences, notifications, watchlist or portfolio to a valid token
is the finding this sprint's review exists to catch, and this week there are four services to
leave it out of.

The one place this gets interesting is the internal call. Notifications asks preferences for a
channel while nobody is logged in, and watchlists asks notifications to deliver in the same
situation. Neither caller holds a customer's token, and reusing one would turn a fifteen-minute
credential into a permanent one. Decide how a service authenticates to a service, and write the
entry.

**Each one runs on live data at the demonstration.** Real quotes from the Fauxnance API, real
messages from the topics your poller and executor are producing, real rows from your Postgres.
Not fixtures, not a seeded response, not a recorded payload replayed from a file. Fixtures
belong in the test suite, and a demonstration that runs on them is demonstrating the fixture.

**One OWASP security review covers all four.** One document, not four concatenated. See below.

Two platform rules carry over unchanged. The Fauxnance key is read from the environment and
never reaches the browser. Every consumer sets an explicit `group.id`, listed in the service
README, and does not share it with another service. You are adding two consumers this week and
both of them read topics something else is already reading.

## Splitting four services without four silos

Four services and one team is an obvious split and the wrong one. One person per service
produces four people who can each explain a quarter of the deliverable, three of whom are
blocked on the fourth by Tuesday, and a showcase where every question goes to whoever wrote
that part. Every member is expected to walk any of the four unaided.

What works better is splitting by the order of the chain rather than by the service. The chain
is built in sequence anyway, so pair on preferences until its API is real and its persistence
works, then move the pair onto notifications while somebody else hardens preferences against
the security review, then onto watchlists. Portfolio and P&L runs in parallel throughout,
because nothing waits on it, and it is the natural place for whoever wants a contract to build
against rather than an API to design.

Three things are worth agreeing on Monday whichever way you split.

Agree the interfaces between the services before you build either side. The route notifications
calls on preferences, and the route watchlists calls on notifications, are the two seams in this
week's work. Write both down on Monday and both sides can build against something.

Rotate before the last day, not on it. Somebody who first opens the watchlist consumer on
Friday afternoon cannot answer a question about it on Friday afternoon.

Fix the scope of each service when you agree it and be willing to cut inside a service rather
than drop one. Four narrow services that integrate beat three finished services and one that
was never started, because the criteria are about the chain working end to end.

## The decision log

Committed in `decision-log/`, one file per decision, using the shape in
[decision-log/TEMPLATE.md](decision-log/TEMPLATE.md). It is an acceptance criterion.

Write entries as you take the decisions. A log assembled in the last hour of the sprint records
what you built, which everyone can already see, and loses the thing that makes it worth
reading: what you nearly did instead, and why you did not. It also reads exactly like what it
is.

An entry is worth writing when reversing the choice later would cost more than an afternoon,
when a competent engineer would have chosen the other option, or when somebody on the team
asked why and the answer took a paragraph. The manifest asks for six, and a week with four
services and two integration seams in it produces more decisions than a week with one service,
not fewer.

The entries worth having this week are mostly about the seams rather than about any one
service. What notifications does when preferences does not answer. Whether a service calls
another service with a service credential or with something else. What happens to an alert
whose delivery fails. Which service owns the customer's contact details, given that storing a
second copy doubles the number of places a leak can happen. Those are the ones a reader in the
cloud week will want, and each of them is a decision two people on the team will remember
differently by Friday.

### A worked entry

Neutral subject, so that the shape is visible without the content doing the work for you.

````markdown
# 0003 One consumer group per service, sized to the partition count

| Field | Value |
|---|---|
| Status | accepted |
| Date | 2026-10-06 |
| Decided by | the whole team, at the Tuesday stand-up |

## Context

The watchlist service consumes `market-data`, which `contracts/kafka-topics.md` fixes at six
partitions because it carries the highest message rate on the platform. We intend to run more
than one instance in Docker Compose so that we can show what happens when one is killed. Kafka
assigns partitions to consumers within a group, so how we set `group.id` decides whether a
second instance shares the work or duplicates it.

## Options considered

| Option | For | Against |
|---|---|---|
| One group for the service, one consumer per instance | Partitions are split across instances, so work is shared and a lost instance is rebalanced onto the others | Only useful up to six instances, since a consumer beyond the partition count is idle |
| A group per instance | Every instance sees every message, which is simple to reason about | Every instance does the same work, and every alert would be evaluated and delivered as many times as we have instances |
| One consumer, no scaling | Nothing to configure | A single point of failure, and no way to demonstrate a rebalance |

## Decision

One group, `watchlist-service`, with each instance running one consumer, and no more than six
instances. The second option is not a scaling design at all: with this service the duplicate
work is a duplicate customer notification, which is a defect a customer sees rather than wasted
CPU.

## Consequences

Scaling past six instances buys nothing, and we have written that in the service README next to
the compose entry. A rebalance pauses consumption briefly when an instance joins or leaves, so
alert evaluation has to be idempotent on `eventId` anyway, which we were going to need for
at-least-once delivery. The group identifier is now part of our operational surface: another
service adopting the same name would silently take half our messages, which is why it is listed
in the README.
````

What makes that entry useful is not its length. It states what was true when the decision was
taken, gives an option that was genuinely considered and rejected, names the thing that decided
it, and admits a cost. An entry with one option in it is a record of what you did.

## The security review

One OWASP review across the four services, committed in this folder, using the shape of the
template at `../sprint-08-auth-service/security-review/TEMPLATE.md`. Copy it, retitle it, and
name your copy in `manifest.env`.

Three things change from Sprint 8. The categories are the full Top Ten, because four services
that consume events, call each other, call a third party and serve a customer touch more of the
list than an authentication service did. A category that applies to none of the four is
dispositioned as out of scope with the reason, not deleted: a category with nothing in it is
the one worth asking about.

The second change is that the review is one document. That is harder than four and it is the
point. A category rarely lands the same way on all four services, and the row worth reading is
the one that says where it landed differently: injection means one thing in the service that
builds a query from a symbol a customer typed and another in the service that only reads its
own tables. Write the finding per category, and name the service or services it belongs to.
Four reviews stapled together will read as four reviews stapled together.

The third is that findings have to be addressed. The criterion is not a review that exists, it
is a review whose findings were dealt with. Fixed, with the commit. Mitigated, with what limits
the exposure. Accepted, with the residual risk stated and named as a decision the team took. A
finding still open on Friday belongs in the outstanding items table with an owner against it,
and it will be asked about.

Start with the access-control row. Every brief in this folder names the same first risk,
because all four services hold data belonging to one customer and reachable with a token
belonging to another.

Two risks are specific to this week and worth looking for by name. A route that another service
calls, reachable by a customer with a customer's token, is an access-control failure the
Sprint 8 review had no equivalent of. And a customer-supplied destination that a service then
posts to, which is the shape a notification channel takes if nobody thinks about it, is a
server-side request forgery.

## What is in this folder

```
README.md              this brief
catalogue/             four briefs, one per mandatory extension, plus stretch.md
decision-log/          TEMPLATE.md, and your entries beside it
manifest.env           the names the harness reads
scripts/check.sh       the acceptance harness
```

Your services do not live here. Each lives in `services/<name>/` with the rest of the platform,
and each goes into `docker-compose.yml` like everything else you have built. This folder holds
the sprint's documents and the harness that reads them.

Your security review goes in this folder. The default name in `manifest.env` is
`security-review/REVIEW.md`.

[catalogue/stretch.md](catalogue/stretch.md) describes the two extensions in the catalogue that
are not mandatory here. They are stretch goals and they are available only once all four
services pass the harness.

## The harness

`scripts/check.sh` runs in two modes and reads every name it needs from `manifest.env`, so it
asserts your design rather than dictating one.

**Static mode** is the default: no running service. It reads the manifest, confirms the four
briefs are where it expects them and that you have declared four services on four different
ports, counts the decision log entries that are not the template, and reads your combined
review: that it exists, that it is not the template, that every category carries a finding and
a disposition, and that all four services are named somewhere in it.

```bash
scripts/check.sh
scripts/check.sh --live
```

**Live mode** needs the whole stack up and starts nothing itself. It signs in once, the way the
Angular application signs in, then puts the same four probes to each of the four services: the
health route answers, the protected route refuses a request with no token, refuses a
well-formed token signed with a key nobody holds, and answers a real one. One token, four
services, each verifying it on its own.

Then it follows the chain as far as it can be followed from outside.

| Probe | What it does |
|---|---|
| Preferences round trip | Writes a channel through your API and reads it back on the route notifications calls |
| Trade event to notification | Runs the command you declared to publish one `trade-events` message, waits, and checks that a notification record appeared |
| Quote to alert | Creates an alert if you declared how, runs the command you declared to publish one `market-data` quote that crosses it, and checks that the alert reads as triggered |
| Alert to notification | Counts notification records either side of that quote, because an alert delivered through a log leaves none |
| Portfolio contract | Reads the summary and positions routes and checks the response shapes against `contracts/portfolio-api.yaml` |

Creating that alert is the only write live mode makes. Everything else it does is a read, so a
run leaves nothing behind but one alert on the demo account.

The two publish commands are yours to declare, because the harness has no Kafka client and will
not guess at your topic configuration, your container names or your envelope. A console
producer, a small script in your repository, or a real order placed through the Trade REST API
all work, and the last is the one closest to the demonstration. Leave a command empty and the
probe it drives becomes a named skip rather than a failure, which is what a Tuesday run should
look like.

Every skip is named and explained. A skip is honest. A green run against something that was not
there is not.

## Acceptance criteria

These are the criteria your instructor assesses against.

1. All four extensions are built and integrated end to end, in the dependency order above.
2. Customer preferences persists a default account and an alert channel per customer, and
   applies them at the customer's next login.
3. Customer notifications consumes `trade-events` and delivers through the channel preferences
   holds.
4. Watchlists and price alerts monitors `market-data` and raises threshold alerts through
   notifications, not to a log.
5. Portfolio and P&L implements `contracts/portfolio-api.yaml` and prices from the Fauxnance
   API.
6. Each service authenticates with the platform JWT.
7. One combined OWASP security review covers all four, and its findings are addressed.
8. An architecture decision log is committed, giving the reasoning for each significant choice.

## Integration quality is read by a person

Say it plainly, because the harness is short enough that a team could mistake a green run for a
finished sprint. It checks that some files exist and say something, that four services answer
three requests each in the right way, and that two things it caused changed something it can
read. That is all it can check.

Everything the criteria turn on is watched by somebody sitting in front of the running chain.
Whether the channel a notification went out on came from the preferences service or from a
constant in the notifications service. Whether the customer's stored default account is applied
when they sign in again, rather than stored and ignored. Whether a replayed event produces one
message or two. Whether an alert reaches a customer or a log file. Whether the portfolio numbers
came from a live quote or a fixture. Whether the scope you agreed on Monday is the scope you
delivered.

Every member of the team is expected to walk any of the four services unaided at the showcase,
including the ones they did not write.

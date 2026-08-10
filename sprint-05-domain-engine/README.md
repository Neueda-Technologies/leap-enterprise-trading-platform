# Sprint 5: the trading domain engine

An order is refused for a reason. The account does not exist. The account is
suspended. The instrument stopped trading last month. The cash is not there.
The customer already sent this exact order and it was accepted the first
time. Those reasons are the business. Everything around them is transport,
and transport changes.

It changes twice in the next fortnight. In Sprint 6 you wrap these rules in a
Spring Boot controller and they run inside one HTTP request. In Sprint 7 the
same rules are called again from a Kafka consumer, in a different process,
minutes later, against a price that did not exist when the order was placed.
If the rules live in the controller, the Trade Executor has to reimplement
them, and the two copies drift. The first time they drift, the platform
accepts an order the executor then refuses, and a customer watches an order
sit at `NEW` forever.

So the rules live here instead, in a plain Java library that neither of those
two callers can bend. No Spring on the classpath. No JDBC driver. No HTTP
client. Nothing that has to be started before a test can run. Sprint 6 adds a
transport around this module and Sprint 7 adds a second one, and neither
should force you to rewrite a rule.

The second reason is cheaper to demonstrate and matters as much. A rule
that can only be exercised by starting Postgres and posting JSON at it is a
rule nobody tests. Every rule in this brief is provable with plain objects in
a few milliseconds, which is why the acceptance criteria can insist the tests
came first.

## What you deliver

| Deliverable | Where it lives |
|---|---|
| Four entities: `Account`, `Instrument`, `Order`, `Position` | `src/main/java/`, under your base package |
| Three enumerations: `AccountStatus`, `OrderSide`, `OrderStatus` | as above |
| The order request DTO, with validation | as above |
| An exception hierarchy covering the six specified cases | as above |
| Business rules 1 to 8, in the domain | as above |
| JUnit 5 tests, written first | `src/test/java/` |
| A UML class diagram and an order placement sequence diagram | `design/` |
| The manifest telling the check harness your names | `manifest.env` |

The scaffold gives you the Maven build, the source tree, the dependency ban
and the harness. Every type in the table is yours to write. There are no
stubs to fill in, deliberately: designing the types from the requirements is
the assessment.

## The domain model

Sprint 3 gave you this domain as tables. Here it is again as objects, and the
two are not the same exercise. A table stores state. An object owns the
behaviour that changes that state, and the point of this sprint is that a
balance is never changed by anything except the account that holds it.

### Account

A customer trades through an account. It holds a cash balance in one
currency, carries the holder's name, and knows whether it is allowed to
trade. It answers whether it can afford a given amount, and it is the only
type that moves its own balance. A debit that would leave the balance
negative is refused before anything is subtracted, not attempted and then
inspected for a negative result.

An account carries two identifiers and they are not interchangeable. The
numeric key is what `accountId` means everywhere in `contracts/trade-api.yaml`,
in the JWT claim and on every order. The customer-facing string reference is
the one quoted on a support call. Sprint 3 already made you keep both.

Order placement contends on this row harder than on anything else, so the
account also carries the version that the persistence layer will use for
optimistic locking in Sprint 6. The domain does not take the lock. It reports
the version it was loaded at.

Money is decimal, at two decimal places, and never a `double`. Binary
floating point cannot represent 0.10 exactly, and a balance that is out by a
hundredth of a penny after a thousand trades is a defect an auditor finds
before you do.

### Instrument

Reference data: a symbol in the Fauxnance scheme, a display name, an asset
class and a currency of quotation. The symbol is the natural key, because the
venue assigns it, it is stable, and it already appears on every order.

An instrument can stop being tradable without ceasing to exist. Delisting is
a flag, never a deleted row, because the order history references the symbol
and that history is the audit trail. Answering whether an instrument may be
traded is business rule 3.

### Order

An instruction to buy or sell a quantity of one instrument at a stated price,
against one account. It is recorded when it is received, before anyone knows
whether it will succeed, because the instruction is the thing the firm is on
the hook for.

An order starts at `NEW` and reaches exactly one terminal state. Terminal
means terminal: a filled order is never reopened, and a transition that is
not allowed is refused by the order itself rather than by whoever called it.

Two prices live on an order and they are different things. The limit price is
what the customer submitted. The executed price is what the Trade Executor
achieved against a live quote in Sprint 7, and it does not exist until the
order is filled. A report that treats the limit price as the traded price is
wrong.

### Position

The net holding of one instrument in one account, with its average cost. It
is derived state: every position in the platform can be rebuilt from the
order history, and you should be able to prove that it can.

The average cost rule is asymmetric, and the asymmetry is the requirement. A
buy recalculates the average across the old holding and the new units at the
price they were bought at. A sell reduces the quantity and leaves the average
cost alone. Keeping the cost basis intact through a sale is what makes
realised profit and loss computable at the point of sale, and the Sprint 10
Portfolio extension depends on it.

Short selling is out of scope, so a position never goes negative.

### The three enumerations

These are fixed. They appear in `contracts/trade-api.yaml`, the Angular UI
generates its types from that file in Sprint 9, and the database stores the
same strings. A renamed or extra literal is a break in three places at once.

| Enumeration | Literals, exactly |
|---|---|
| `AccountStatus` | `ACTIVE`, `SUSPENDED`, `CLOSED` |
| `OrderSide` | `BUY`, `SELL` |
| `OrderStatus` | `NEW`, `FILLED`, `REJECTED`, `CANCELLED` |

`ACTIVE` accounts trade. `SUSPENDED` accounts can be read and cannot trade,
and the suspension is reversible. `CLOSED` accounts never trade again and are
never deleted.

`NEW` is the working state, held from acceptance until the order is resolved.
`FILLED`, `REJECTED` and `CANCELLED` are terminal. There is no partial-fill
literal, which is why the Trade Executor fills in full or rejects.

Spell `CANCELLED` with two `L`s. The harness names the literal it could not
find, and this is the one it finds missing most often.

### The order request DTO

A request to place an order carries six fields. The schema is
`PlaceOrderRequest` in `contracts/trade-api.yaml` and it is binding.

| Field | Constraint |
|---|---|
| `accountId` | Required. The numeric account key, at least 1 |
| `symbol` | Required, not blank, at most 20 characters |
| `side` | Required, one of `BUY` or `SELL` |
| `quantity` | Required, whole units, greater than zero |
| `price` | Required, greater than zero, at most two decimal places |
| `idempotencyKey` | Required, between 8 and 100 characters |

The DTO lives in the domain rather than in the Sprint 6 service, because
those constraints are business constraints and not transport constraints.
Quantity greater than zero is business rule 4 and price greater than zero is
business rule 5. A second caller of this library gets the same constraints
without reimplementing them.

Bean Validation annotations are the one framework the architecture allows
inside the domain, and `jakarta.validation-api` is the only compile
dependency in the scaffold. They are declarations rather than behaviour, and
nothing that opens a socket or a connection joins them. If you would rather
validate by hand, the criteria do not stop you: what is assessed is that
every constraint in the table is enforced and tested.

## The exception hierarchy

Six cases are specified. Every one of them extends a single domain base type,
so that the Sprint 6 service can catch the base in one place and map it, and
so that a new rule cannot be added without deciding what it means to a caller.

| # | Case | Raised when | Code |
|---|---|---|---|
| 1 | Account not found | No account exists with the key on the request | `ACC-404` |
| 2 | Account not active | The account exists and is `SUSPENDED` or `CLOSED` | `ACC-403` |
| 3 | Instrument not found | The symbol is unknown, or it is known and no longer tradable | `INS-404` |
| 4 | Insufficient funds | A buy costs more than the available cash balance | `ORD-400` |
| 5 | Insufficient holdings | A sell is larger than the quantity held | `ORD-409` |
| 6 | Duplicate order | The idempotency key has already been accepted | `ORD-409` |

Four things about the hierarchy are assessed.

**The base type carries the catalogue code, not an HTTP status.** The codes
are the ones in `contracts/trade-api.yaml`, and the client branches on them.
The domain has no opinion about HTTP: Sprint 6 maps a code to a status in one
place, and the Trade Executor in Sprint 7 maps the same code to a rejection
reason on a Kafka event. Put a status on the exception and you have dragged
the web layer into the domain a sprint early.

**One code can mean two things and one case can carry two codes.** An unknown
instrument and a suspended instrument both answer `INS-404`, because the
caller has no need to tell them apart. Insufficient holdings and a duplicate
order both answer `ORD-409`. Neither is an accident.

**The message is the catalogue message and nothing else.** It becomes the
response body. No account key, no symbol, no amount, no class name, no SQL
fragment. Values needed for an investigation belong on the exception as typed
fields, and are logged on the server. Leaking internal detail in an error
body is OWASP A05, which you covered in Sprint 2.

**Rules 4 and 5 have a code and no specified exception.** The list of six has
no member for a quantity or a price that is out of range, and `VAL-422` is
still a documented outcome of order placement. Decide what your hierarchy
does about that and be ready to defend it in the review. Adding a type is a
reasonable answer. So is a considered argument that validation alone covers
it, provided you can say what happens when the caller is the Trade Executor
replaying an order and never ran a validator.

The harness reads the six names from `manifest.env`. Any addition of your own
is your business and is not checked.

## Business rules 1 to 8

These are the rules the curriculum numbers, and the acceptance criteria refer
to them by number. They are enforced in this order. The first failure wins
and no later rule is evaluated.

| # | Rule | Case raised | Code |
|---|---|---|---|
| 1 | The account must exist | Account not found | `ACC-404` |
| 2 | The account must be `ACTIVE` | Account not active | `ACC-403` |
| 3 | The instrument must exist and be tradable | Instrument not found | `INS-404` |
| 4 | Quantity must be greater than zero | see above | `VAL-422` |
| 5 | Price must be greater than zero | see above | `VAL-422` |
| 6 | On a `BUY`, the cash balance must be at least quantity multiplied by price | Insufficient funds | `ORD-400` |
| 7 | On a `SELL`, the held quantity must be at least the order quantity | Insufficient holdings | `ORD-409` |
| 8 | The idempotency key must not already have been used | Duplicate order | `ORD-409` |

Rules 9 and 10 carry no error code and are not part of this sprint's
countable criteria, but the design has to leave room for them. Rule 9: cash
and position move together or neither moves. Rule 10: every order is
recorded, including a rejected one, because the order table is the audit
trail. A domain object that has already been half mutated when a precondition
fails depends on somebody remembering to roll back a transaction, and that
somebody does not exist yet in Sprint 5.

Four points decide whether the rules are implemented well or merely present.

**The order is part of the contract.** A request that breaks two rules
receives the code of the first one, and the Angular order ticket branches on
that code in Sprint 9. A suspended account holding no cash gets `ACC-403`,
not `ORD-400`. Test the ordering itself, not only the eight rules.

**They belong to the domain, not to a controller.** This is the criterion
that fails most often, because the shortest route to a working Sprint 6 is an
`if` in the controller. The harness cannot see a controller you have not
written yet, so nothing stops you this week. Sprint 6 does, and by then the
rework is expensive.

**Rules 4 and 5 are checked twice on purpose.** The DTO constraints are a
syntactic gate that the Sprint 6 service runs before the rules are reached.
The rules check the same two values again, because the domain has to hold for
a caller that never ran a validator. The duplication is not a mistake to
tidy up.

**Rule 8 is stated here and enforced elsewhere.** In Sprint 6 the authority
is the unique constraint on `orders.idempotency_key` that you built in
Sprint 3, not a read followed by a write. Two concurrent requests carrying
the same key both pass a read-then-write check, and the side effect of losing
that race is a duplicated trade. The rule still has to be expressible and
testable here without a database, so design the seam that lets it be. What
that seam looks like is your decision, and you will be asked about it.

## Test-driven development

The tests come first. That is a criterion, not a preference, and it is
assessed from the commit history rather than from the final state of the
repository, because a suite written on Thursday afternoon and a suite written
alongside the code are indistinguishable once both are green.

Evidenced in commit history means an assessor can open `git log` and see the
cycle. One acceptable shape, per rule or per behaviour:

1. A commit that adds a failing test and nothing else. The message says what
   the test asserts. The build is red at this commit and that is the point.
2. A commit that adds the smallest implementation that turns it green.
3. A commit that refactors with the test still green, where there is
   something to refactor. Not every cycle has this one.

Other shapes pass. A commit that adds three related failing tests, then one
that turns them green, is fine. What does not pass is a history in which the
test for a rule and the implementation of that rule first appear in the same
commit, and what fails outright is a single commit at the end of the week
holding the whole module. Commit small, commit often, and push as you go so
the history exists somewhere other than one laptop.

Three test classes are named in the acceptance criteria and all three must be
green.

| Class | Covers |
|---|---|
| `AccountTest` | Status, debit, credit, affordability, the refusal to go negative, and money that does not drift over many operations |
| `OrderLogicTest` | Business rules 1 to 8, each one firing and each one not firing, plus the evaluation order itself |
| `PlaceOrderRequestValidationTest` | Every constraint on the DTO, including the boundary either side of each limit |

Name them exactly that. The packages are yours. Write the other classes you
need for the entities you are not asked about by name: the criteria set a
floor, not a target.

The harness requires at least 24 tests across those three classes. That
number is arithmetic rather than ambition. Eight rules firing and eight not
firing is 16 in `OrderLogicTest` alone, six DTO fields is six more, and
`AccountTest` cannot cover the list above in fewer than a handful.

## The UML diagrams

Two diagrams, committed to `design/`.

**A class diagram of the domain.** Every type you wrote, its fields, the
operations that carry behaviour, the enumerations, the exception hierarchy,
and the relationships between them with their cardinality. It is a picture of
your design, not of the reference model in this brief.

**A sequence diagram of order placement through the rules.** One order
arriving at the domain and the eight rules being evaluated against it, in
order, showing what is consulted at each step and where each failure leaves
the flow. Draw the refusal paths, not only the happy path. A sequence diagram
that shows an order sailing through eight boxes and coming out accepted has
not documented the interesting half of this module.

Two formats are acceptable:

- Mermaid in a markdown file, `design/class-diagram.md` and
  `design/sequence-diagram.md`, using `classDiagram` and `sequenceDiagram`
  blocks. This is the better choice, because it diffs in review and it cannot
  drift out of the repository.
- An exported image, `.png` or `.svg`, from whatever tool you drew it in.
  Commit the export, not a link to a cloud document your instructor cannot
  open in the review.

The review walks the diagram against the code. An assessor picks a class off
the diagram, opens it, and expects the fields, the operations and the
relationships to match. They then pick a rule off the sequence diagram and
expect to find it where the diagram says it is. Diagrams drawn on Monday and
never updated fail that walk, so update them when the code moves. Every team
member walks the whole diagram, including the parts they did not write.

## The toolchain

Java 21 and Maven 3.9 or later. JUnit 5 for tests. Nothing else, and the
build is configured to keep it that way.

```bash
sprint-05-domain-engine/scripts/check.sh    # the acceptance harness

cd sprint-05-domain-engine
mvn test                                    # the suite
mvn install                                 # publish to your local repository
```

`mvn install` matters from Sprint 6, when the Trade REST API resolves this
module from your local Maven repository by its coordinates. There is no
aggregator build, so an install here has to happen before a package there.

The `pom.xml` carries a banned-dependencies rule that fails the build if
Spring, a servlet API or a JDBC driver appears anywhere in the tree,
including transitively. That rule is the criterion "no database, HTTP or
Spring dependency in the domain module", enforced by the build rather than by
good intentions. Do not remove it. If you find yourself wanting to, the thing
you are about to add belongs in Sprint 6.

Nothing in this sprint needs Docker. The suite starts no container, opens no
socket and reads no environment variable, and it should stay that way.

## Acceptance criteria

These are the criteria your instructor assesses against.

1. `Account`, `Instrument`, `Order` and `Position` match the domain model.
2. `AccountStatus`, `OrderSide` and `OrderStatus` match exactly.
3. The exception hierarchy covers all six specified cases.
4. Business rules 1 to 8 are implemented in the domain, not in a controller.
5. No database, HTTP or Spring dependency in the domain module.
6. Tests are written before implementation, evidenced in commit history.
7. `AccountTest`, `OrderLogicTest` and `PlaceOrderRequestValidationTest` are
   all green.
8. UML class and sequence diagrams are committed and match the code.

## The check harness

`scripts/check.sh` asserts the things a machine can assert. Run it as often
as you like. It needs no database and no container, and it never calls
Fauxnance, so it costs nothing against your quota.

```bash
sprint-05-domain-engine/scripts/check.sh
```

| Check | What it proves |
|---|---|
| `mvn clean test-compile` succeeds from a clean state | Criterion 5, the build half. The module compiles from the files in the repository, not from something cached on one laptop |
| The whole suite passes | The floor for criterion 7 |
| The three named test classes each produced a report | Criterion 7, by name |
| At least 24 tests across those three | Criterion 7, the countable half |
| The three enumerations exist under your base package | Criterion 2, the existence half |
| Each holds exactly the contractual literals, no more and no fewer | Criterion 2, the exact half |
| Six exception types exist, all descending from one domain base | Criterion 3 |
| `mvn dependency:tree` contains no Spring, servlet or JDBC artefact | Criterion 5, the dependency half |

It reads your base package and your six exception class names from
`manifest.env`, so it asserts your design rather than dictating one. The
enumeration names and the three test class names come from the acceptance
criteria and are not yours to choose.

The enumeration and exception checks read compiled classes with `javap`
rather than reading your source, so a literal that is commented out, declared
in a string or spelled differently in two places is caught rather than
matched. A failure names the literal that is missing and the literal it found
instead.

### What passing does not mean

The harness counts tests, it does not read them. A test that asserts nothing
passes here. It confirms that eight rules could be implemented, and it has
never placed an order.

Assessed by a human at the design review, and not by this script:

- whether each of the eight rules is correct, in the right order, and in the
  domain rather than in a caller
- whether the commit history shows tests arriving before implementation
- whether the two diagrams match the code they claim to describe
- whether your seam for rule 8 survives two concurrent requests
- whether every member of the team can walk the model unaided

Bring to the review: the diagrams, the `git log`, one rule traced from its
first failing test to the code that satisfies it, and your answer to why the
evaluation order is what it is.

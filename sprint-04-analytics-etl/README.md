# Sprint 4: analytics and the ingestion pipeline

The schema you designed last week answers one kind of question. What is this
account's balance. What is open on this account right now. Those are answered
by touching a handful of rows, in milliseconds, thousands of times an hour,
while orders are being written to the same tables.

The desk asks a different kind. What did we trade last quarter, by instrument,
by week. Which names moved most, and when. That question reads millions of
rows and aggregates them, and running it against the operational tables makes
order placement slow for everybody while it runs. Worse, it makes the answer
depend on when you asked, because the rows are changing underneath the query.

So the two live apart. An operational store shaped for correctness under
concurrent writes, and an analytical store shaped for reading a lot of history
at once. Something has to move data from the first into the second on a
schedule, reshaping it on the way. That something is a pipeline, and this
sprint is where you build your first one.

## Why the data is market data this week

The platform's own order flow does not exist yet. The Trade REST API arrives
in Sprint 6, and the Trade Executor that fills an order arrives in Sprint 7.
The only trades in your database are the ones you seeded by hand last week. A
pipeline over thirty rows you invented teaches nothing, and a dashboard over
them says nothing.

Market data is available today. The Fauxnance API serves end-of-day candles
going back years, for US and Indian equities, foreign exchange and crypto. It
is authenticated, rate limited, occasionally missing a day, and occasionally
wrong, which is what makes it worth building against. The awkwardness is the
lesson.

This is deliberate rather than a compromise. In Sprint 7 you point the same
three functions at the platform's own trades and load the star schema in
`contracts/analytics-schema.sql`. The source changes. The shape of the
pipeline, the way it handles a bad row, and the tests around the transform do
not. Build it this week as though the source were going to change, because it
is.

## What you deliver

| Deliverable | Where it lives |
|---|---|
| The pipeline, as three separable functions | `src/analytics/etl/` |
| The Fauxnance client, with the key from the environment | `src/analytics/fauxnance/` |
| The dashboard, and the chart artefacts it writes | `src/analytics/dashboard/`, artefacts committed at the paths you name |
| Three business claims, each naming the chart that supports it | `claims.md` |
| pytest over at least the transform, including a malformed-input case | `tests/` |
| The manifest that tells the check harness your names | `manifest.env` |

The scaffold gives you the package layout, the dependency set, the canned
fixtures and the harness. Every function in it is yours to write.

## What a business claim is

A claim is a sentence about the business that could turn out to be wrong. It
names what is true, of what, over what period, and by how much. Someone
reading it can disagree with it, and going and checking the data would settle
the disagreement.

A chart description is not a claim. It tells the reader what the picture is of
and leaves them to work out whether anything follows.

Worked example, from a parcel carrier rather than a trading desk, so that
nothing here is one of your three:

> **Chart description.** This chart shows average parcel transit times by
> depot over the last six months.

> **Claim.** Parcels routed through the Leeds depot arrive a full day later
> than the network average, and the gap has widened every month since March.

The second one names a subject, a magnitude, a direction and a period. It
tells an operations manager where to look on Monday morning. The first tells
them a chart exists.

Supported by a chart a non-technical reader can read unaided means what it
says. Both axes labelled, with units. A title that states the finding rather
than naming the variables. No unexplained abbreviation, no ticker without a
company name, no legend entry that only makes sense to the person who wrote
the query. The reader has your chart and no access to you.

Three claims, minimum. State each one in `claims.md` alongside the artefact
that backs it.

## The pipeline

Three steps, three functions, three modules, wired together by a fourth that
does nothing else.

**Extract** obtains raw responses and hands them on unchanged. It is the only
part that needs a key and a network.

**Transform** takes data and returns data. Parsing, typing, cleaning,
aggregating, deriving. It opens no socket, reads no environment variable and
writes nowhere. That is what makes it cheap to test, which is why the criteria
insist it is tested.

**Load** writes the result into the analytical store and is the only part that
writes.

The split earns its keep the first time something breaks. A pipeline that
fetches, cleans and writes in one function can only be tested by running the
whole thing against the live API, and when it produces a wrong number there is
no way to ask which third of it was wrong.

Keep them individually callable. The harness imports each of the three by name
from `manifest.env` and asserts they are three functions in three modules.

### Caching

Cache raw pulls to disk. One symbol over one date range is one request against
a quota of 2000 per day, and a team debugging a chart runs the pipeline twenty
times before lunch. Write the raw response to `.cache/` keyed by symbol and
range, read it back when it is already there, and re-runs cost nothing.

Cache the raw response, not the cleaned frame. Changing the transform is the
thing you will do most this week, and it should not need a fresh pull.

## The key and the quota

The key is read from `FAUXNANCE_API_KEY` and from nowhere else. Copy
`.env.example` at the repository root to `.env`, which is git-ignored, and put
your key there. It is never a literal in source, never in a test, never in a
fixture, never in a notebook you commit. A key that reaches a commit has to be
revoked, and the history keeps it whether or not you revoke it.

The quota is 2000 requests per day per key, and this sprint uses very few of
them. A year of daily candles for one symbol is one request. Eight symbols is
eight requests. With a cache on disk, a full team working all day stays in the
low tens of requests, well inside one person's allowance. A team that runs out
this week has a bug, almost always a pull inside a loop that should have been
a cache lookup.

Check where you stand with `GET /usage` before assuming the API is broken, and
`GET /health`, which needs no key, before assuming anything at all.

## Error handling

A bare `try` around the whole run does not meet the criteria, because it
cannot tell these four apart and they need different answers.

| What happened | How you know | What to do about it |
|---|---|---|
| The daily quota is exhausted | HTTP 429, with `Retry-After` giving the seconds until it resets at midnight UTC | Stop, and say so plainly. Sleeping until midnight inside a batch run is not recovery |
| The request itself is wrong | Another 4xx: 401 for a bad or missing key, 404 for a symbol Fauxnance does not serve, 400 for a range over ten years | Fail this symbol, keep the message, and carry on with the others. Retrying repeats the mistake |
| Nothing reached the service | A connection error or a timeout from `requests` | Retry with a backoff that grows, and give up after a small number of attempts |
| The response arrived and is wrong | HTTP 200 with a candle missing a field, a price that is not a number, a high below a low | Not an HTTP problem. This belongs to the transform, and the transform decides between dropping the row, quarantining it and raising |

Log enough that a teammate can tell which of the four happened without
rerunning it. Never log the key.

## Testing

pytest, over at least the transform, including at least one malformed-input
case. That is the floor rather than the target.

The suite never touches the network. `fixtures/` holds three canned responses
in the real envelope shape, one of them deliberately corrupted, and
`tests/conftest.py` loads them for you. A suite that needs the API to be up
fails on a train and gets skipped by the third person who sees it fail.

`fixtures/README.md` lists the six defects in the malformed payload. Decide
what your transform does with each, then assert it. Dropping a row,
quarantining it and raising are all defensible, and they are not equally
defensible for all six. What is not defensible is loading a row that says a
share traded at a high below its low and then drawing a chart from it.

Declare the test that covers the malformed case in `manifest.env` as a pytest
node id. The harness runs that one test on its own.

`tests/test_example_fixture_use.py` is an example of the mechanics and nothing
more. It asserts things about the canned data rather than about your code.
Delete it once your own tests use the fixtures.

## The dashboard

One artefact per claim, or one file holding all three charts, committed either
way. plotly can inline its own JavaScript, so an HTML report opens with no
network and no build step. A dashboard that only exists while a notebook
kernel is running cannot be assessed, and a chart that loads its library from
a content delivery network is a blank page on a locked-down machine.

Name the artefacts in `claims.md`. Where one file holds several charts, point
at the chart inside it with a fragment, for example
`report.html#transit-times`.

## How you work

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -e 'sprint-04-analytics-etl[dev]'
.venv/bin/python -m pytest sprint-04-analytics-etl
```

Give the pipeline an entry point a teammate can run without reading the
source, either a `[project.scripts]` entry in `pyproject.toml` or a `__main__`
block, and say which in a note at the bottom of `claims.md`.

Write the transform tests as you write the transform, not on Thursday. The
malformed fixture is in the repository from day one for that reason.

## Acceptance criteria

These are the criteria your instructor assesses against.

1. Three or more insights, each stated as a business claim and supported by a
   chart a non-technical reader can read unaided.
2. Fauxnance candles pulled through `GET /candles/{symbol}`, with the key read
   from the environment.
3. The pipeline is separated into extract, transform and load functions.
4. pytest covers at least the transform step, including one malformed-input
   case.
5. Rate-limit and error handling are present, and not a bare `try` block.

## The check harness

`scripts/check.sh` asserts the things a machine can assert. Run it as often as
you like. It needs no database and no container, and it never calls Fauxnance,
so it costs nothing against your quota.

```bash
sprint-04-analytics-etl/scripts/check.sh
```

It builds a scratch virtual environment at `.check-venv/`, installs the
package into it, and runs your suite there. Pass `--reuse` to keep the
environment between runs once you are iterating, and `--keep` to leave it in
place after a run that passed so you can run pytest in it yourself.

| Check | What it proves |
|---|---|
| The package installs into an empty environment | It is a package a teammate can install, not a folder that works on one laptop |
| The three functions named in `manifest.env` import and are callable | Criterion 3, the countable half |
| Those three live in three different modules | Separable rather than three names in one file |
| Code under `src/` names `FAUXNANCE_API_KEY`, in code rather than in a comment | Criterion 2, the weak half |
| No key literal, and no base URL carrying a key, under `src/`, `tests/`, `fixtures/` or in `claims.md` | The key is not in the repository |
| The suite passes and collects at least four tests | Criterion 4, the countable half |
| The test declared as the malformed-input case passes on its own | Criterion 4, the specific half |
| `claims.md` holds three filled-in claims, each naming a chart file that exists | Criterion 1, the countable half |

### How the harness avoids dictating your design

The harness has no pipeline of its own. It reads `manifest.env` to learn what
you called things, then asserts against those names. Declare the three
functions as `module:function`, and the malformed-input test as a pytest node
id such as `tests/test_transform.py::test_rejects_a_high_below_a_low`.

Naming the test rather than matching on a keyword is deliberate. You choose
the name, the harness reports which test it ran when it fails, and nothing
forces a naming convention on the rest of your suite.

### What passing does not mean

The harness runs your malformed-input test, it does not read it. A test that
asserts nothing passes here. It measures the length of a claim, not its truth.
It confirms a chart file exists, and it has never opened one.

Whether the claim holds, whether the chart supports it, whether a reader
outside your team could read that chart unaided, and whether your error
handling is four cases or one bare `try` are assessed by your instructor.

Bring to the review: the three claims, the charts, the numbers behind one of
them traced back to the rows they came from, your transform's decision on each
of the six defects in the malformed fixture, and the answer to "what would
have to be true for this claim to be wrong".

# Planted starter flaws

Status: instructor-only. Do not commit this file to `us-ireland` or to `india`, do not quote it in a sprint brief, and do not hand it to a team that asks what is wrong with the loader. Finding these is the exercise. A team given the list has been handed the answer to the only question Sprint 7 asks them.

This is the record of the deliberate flaws in the batch loader on the `us-ireland` branch, at `sprint-07-event-backbone/etl-starter`. It is the code participants characterise and then refactor. All nine flaws are in `src/etl_starter/loader.py`. The loader runs, it loads, and the Sprint 4 dashboard reads what it produces, which is the point: the behaviour is worth pinning before anybody changes it.

Decision 6 in `DECISIONS.md` limits planted defects to `us-ireland`. The `india` branch ships clean stubs, and its teams characterise their own Sprint 6 code instead, so nothing below applies to that cohort.

## The flaws

1. **There is no extract, transform, load seam.** `run_load()` is one function of roughly 150 lines. It opens both connections, creates the warehouse schema, reads three tables, derives dimension attributes, allocates surrogate keys, inserts every row and prints the summary. Nothing inside it can be exercised without a Postgres database and a DuckDB file, and there is no boundary at which a test could hold a transformed row and assert on it. Sprint 4 asked these teams for extract, transform and load as separate functions. This is what that instruction looks like a year after nobody enforced it.

2. **The warehouse DDL drops the constraints that make the load correct.** The inline `SCHEMA` string is `contracts/analytics-schema.sql` with `uq_fact_trades_source`, `uq_dim_instrument_symbol` and all three foreign keys removed, under a comment claiming the constraints were trimmed to what DuckDB accepts. DuckDB accepts all of them. With them gone, nothing enforces one fact row per source order, nothing prevents a second `dim_instrument` row for a symbol already loaded, and nothing catches a fact row pointing at a dimension key that does not exist. The comment is the interesting part: it is a plausible technical excuse for a correctness decision, and teams tend to believe it until somebody tests it.

3. **There is no watermark.** Every run reads the whole of `orders` and appends. The `--since` argument is state the operator has to remember, not state the loader holds, and nothing records what the last run covered. Run the loader twice against an unchanged source and `fact_trades` holds two rows for every order. The dimensions double as well. The contract asks for an incremental, idempotent load, and this is neither.

4. **`dim_account` is Type 2 in name only.** The table has `effective_date`, `end_date` and `is_current`, and the load ignores what they mean. Every run inserts a fresh row per account with `effective_date` set to today, `end_date` NULL and `is_current` TRUE. No version is ever closed off, so after the second run there is no such thing as the current version of an account, and a query filtering on `is_current` returns one row per run. The change detection that would earn the columns does not exist: the loader never compares a source row against the version it already holds.

5. **Bad rows disappear without trace.** The fact loop is wrapped in `except Exception: continue`, and inside it bare `continue` guards drop any order whose account or symbol did not resolve to a dimension key, and any order with a NULL `created_on`. Nothing is written anywhere, no reason is recorded, and the printed summary counts only the rows that loaded. A run that silently discarded a third of the source looks identical to a clean one. This is the failure the sprint's dead-letter requirement exists to prevent, and the fixtures contain rows that trigger it.

6. **`trade_value` is computed from the wrong price.** The loader always multiplies `quantity` by `price`. `contracts/analytics-schema.sql` states that `trade_value` is quantity multiplied by `executed_price` where the order filled. `price` is the limit price the customer asked for, so every filled order that executed away from its limit carries a value the desk cannot reconcile against the operational database. The `executed_price` column is read from the source and written into the fact table, so the correct input is sitting in the row and going unused. This is the flaw that most often survives a first refactor, because the code looks reasonable and the arithmetic is right.

7. **Configuration is scattered through the function body.** `os.environ` is read at seven points inside `run_load()`, the `WAREHOUSE_PATH` default is spelled out independently at two of them, and the development Postgres password is defaulted inline in the DSN string. There is no configuration object and no single place to read what the process needs in order to run. Change one of the two warehouse defaults and the summary line reports a file the load did not write.

8. **The `--since` value is concatenated into the orders query.** It is string concatenation, not a bound parameter. The value arrives from the command line, which narrows who can reach it, and that is not a reason to leave it standing: this is the pattern Sprint 6 spent a week removing from the MyBatis mappers, reappearing in the pipeline the same teams own. Expect it named as an injection finding, OWASP A03, in the security review, and expect the parameterised fix rather than input validation.

9. **There is no reconciliation and there are no tests.** `tests/` holds a `.gitkeep` and nothing else. No query compares warehouse row counts and summed `trade_value` against the operational database, although the contract names the reconciliation as part of the deliverable and the schema file's comments state what to compare. The loader's only account of itself is four printed lines, and none of them is checked against anything.

## The one deliberate mercy

`dim_date` handling is correct. The loader reads the date keys it already holds, inserts only the days it has not seen, and derives day, month, year, quarter, day of week, day and month names and the weekday flag correctly. It is the one part of the load that is safe to re-run.

That is there so the code does not read uniformly bad. A file in which everything is wrong invites a rewrite: participants delete it, start again, and the outcome the sprint is assessed on, changing code you did not write without changing what it does, never happens. One correct component forces a team to read closely enough to tell the two apart, and it gives them something to point at when they argue about what the original author was and was not careful about.

## What to expect before a refactor lands

Characterisation tests come first, and they pin current behaviour rather than assert correct behaviour. Expect a team's suite to hold at least the following, built on `fixtures/source-rows.json` rather than a live database:

- The row counts and the summed `trade_value` the fixture produces today.
- The `trade_value` currently written for a filled order whose executed price differs from its limit price, recorded as today's output with a note that it is wrong.
- What a second run does to the fact and dimension row counts.
- The fate of each awkward fixture row, meaning which orders reach `fact_trades` and which are dropped.
- The four lines the summary prints, exactly.

A team that writes a test asserting the correct `trade_value` has written a failing unit test, not a characterisation test. Both are worth having, and the difference between them is worth a conversation at the point they show you the suite. What must not pass review is a refactor landing with nothing pinned. The loader produces a warehouse somebody uses, and "it still runs" is not evidence that it still produces the same warehouse.

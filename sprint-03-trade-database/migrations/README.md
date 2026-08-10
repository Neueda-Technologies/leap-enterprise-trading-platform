# Migrations

Every statement that changes the shape of the database lives here, in a `.sql`
file, under version control. Nothing is typed into a psql session and left
undocumented.

## Naming

Three digits, an underscore, a short description in lower case with
underscores:

```
001_create_core_tables.sql
002_add_indexes.sql
003_add_trade_history.sql
```

The number sets the order. Files are applied in filename order, so `010_` must
exist before `100_` does, and three digits leave room for the rest of the
programme. `scripts/check.sh` rejects a file in this directory that does not
match `NNN_name.sql`.

How much goes in one file is your decision. One migration per logical change
is the useful unit: a reviewer should be able to read the filename and know
what moved.

## Immutability

Before your first design review, edit these files freely. You are still
converging on the model and there is no cost to rewriting `001_`.

After the review, and for the rest of the programme, a migration that has been
applied is finished. Add `002_`, then `003_`. Never reopen an old one.

The reason is other people's databases. Once a teammate has run `001_`, their
database records that the file ran. Editing it changes nothing on their
machine and everything on a machine that starts clean, so the two diverge
silently and the difference surfaces as a mapper failure in Sprint 6 that
nobody can reproduce. The same argument applies with more force to Sprint 7,
where dropping and recreating a table means losing the audit trail.

Rolling back is the same rule in reverse. If `003_` was wrong, `004_` corrects
it. The history of what you did is worth keeping.

## Applying them

```bash
sprint-03-trade-database/scripts/apply.sh
```

Applies every migration here in order, then everything in `seed/`. Add
`--fresh` to drop the database and rebuild it from these files, which is the
only way to be sure the files are the whole truth.

## What does not go here

Seed data. Fixture rows belong in `seed/` so that you can reload data without
rebuilding the schema, and rebuild the schema without carrying fixtures into
an environment that should not have them.

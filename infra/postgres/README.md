# Postgres initialisation

Anything you put in this directory is mounted into the container at
`/docker-entrypoint-initdb.d`. Postgres runs every `.sql` and `.sh` file it
finds there, in filename order, the first time the container starts against an
empty data volume. Files with any other extension are ignored, which is why
this README does no harm sitting here.

The directory is empty of SQL because the schema is yours. You design it in
Sprint 3.

Two conventions make this work as a migration mechanism rather than a single
dump. Number your files so the order is explicit and stable, for example
`01-schema.sql` then `02-seed.sql`. Keep the schema and the seed data in
separate files, because you will want to reload one without the other.

The scripts run once and only once. Editing a file here after the volume
exists changes nothing until you reset the volume. See the resetting section
of `../README.md`.

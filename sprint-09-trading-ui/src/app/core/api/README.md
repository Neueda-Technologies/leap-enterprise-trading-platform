# api

Generated code. Nothing in here is written by hand.

`npm run generate` reads `openapitools.json` and writes `trade/` from
`contracts/trade-api.yaml` and `auth/` from `contracts/auth-api.yaml`. Both directories are
committed, so the build works without a Java runtime and a contract change shows up as a
reviewable diff.

Never edit a file under `trade/` or `auth/`. The next regeneration overwrites it, and the
harness diffs your committed clients against a fresh generation and fails when they differ.
When the generated shape is awkward to consume, wrap it in a service in `../services/`.

"""Load: write the clean series into the analytical store.

Responsibility: the only module that writes. It takes a prepared table and
puts it in DuckDB, along with whatever the store needs to be reloadable.

Make the load repeatable. Running the pipeline twice with the same input must
leave the store in the same state as running it once, because you will run it
twice: after a failed run, after a transform change, after a teammate pulls
your branch. A load that appends unconditionally doubles every number on the
dashboard the second time somebody runs it, and the chart still renders, which
is why this defect survives to the review.

The store is a file, not a service. Keep it out of the repository and rebuild
it from the cache and the pipeline. In Sprint 7 this same step loads the star
schema in `contracts/analytics-schema.sql` from the platform's own order flow,
so a load function that assumes candles and nothing else has a short life.
"""

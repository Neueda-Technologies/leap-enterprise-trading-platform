"""The Sprint 7 streaming sink: `trade-events` into `fact_trades`.

Read docs/ARCHITECTURE.md before changing this module: streaming consumption
of `trade-events` is optional and must reconcile against the batch load
rather than replace it. This sink and the batch ETL upsert the same
`fact_trades` row on the same `source_order_id`, which is what makes the two
loaders reconcile automatically rather than by a separate merge job.
"""

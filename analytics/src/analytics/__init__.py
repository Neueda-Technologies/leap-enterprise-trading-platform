"""Enterprise Trading Platform analytics package.

Covers the Sprint 4 and Sprint 7 capstone analytics work: the batch ETL
pipeline, the Sprint 4 dashboard, and the Sprint 7 Kafka sink that lets the
dashboard read a real-time stream alongside the batch load. See README.md
for the architecture and docs/contracts/analytics-schema.sql for the star
schema this package loads.
"""

__all__ = ["__version__"]
__version__ = "0.1.0"

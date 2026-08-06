"""One place for "now", so every `loaded_at` and `processed_at` column in the
warehouse is stamped consistently.

Returns a naive UTC datetime because docs/contracts/database-schema.sql and
docs/contracts/analytics-schema.sql both specify `TIMESTAMP`, not
`TIMESTAMPTZ`, and DuckDB's `TIMESTAMP` column is naive. A timezone-aware
value would still write, but comparing it against the naive values already
in a warehouse file would silently do the wrong thing.
"""

from __future__ import annotations

from datetime import datetime, timezone


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)

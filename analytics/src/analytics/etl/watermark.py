"""The incremental watermark: how `etl run` knows where it left off.

Not part of docs/contracts/analytics-schema.sql. See the note on
`etl_watermark` in analytics/db/schema.sql.
"""

from __future__ import annotations

from datetime import datetime

import duckdb

PIPELINE_NAME = "fact_trades"


def get_watermark(conn: duckdb.DuckDBPyConnection, pipeline_name: str = PIPELINE_NAME) -> datetime | None:
    row = conn.execute(
        "SELECT last_loaded_at FROM etl_watermark WHERE pipeline_name = ?",
        [pipeline_name],
    ).fetchone()
    return row[0] if row else None


def set_watermark(
    conn: duckdb.DuckDBPyConnection, last_loaded_at: datetime, pipeline_name: str = PIPELINE_NAME
) -> None:
    conn.execute(
        """
        INSERT INTO etl_watermark (pipeline_name, last_loaded_at)
        VALUES (?, ?)
        ON CONFLICT (pipeline_name) DO UPDATE SET last_loaded_at = excluded.last_loaded_at
        """,
        [pipeline_name, last_loaded_at],
    )

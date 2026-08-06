"""The operational side: a read-only SQLAlchemy engine onto Postgres.

Connects with the `analytics_reader` role described in
docs/contracts/database-schema.sql. The ETL never issues an INSERT, UPDATE or
DELETE against this engine; it only ever SELECTs.
"""

from __future__ import annotations

from sqlalchemy import Engine, create_engine

from analytics.config import PostgresSettings


def get_engine(settings: PostgresSettings) -> Engine:
    return create_engine(settings.sqlalchemy_url, pool_pre_ping=True, future=True)

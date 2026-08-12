"""Environment configuration.

Every setting is read from the environment, with a sensible local default
where the contracts define one. Nothing here reads a config file: a training
pipeline that reads twelve places for one setting is harder to debug than
one that reads the environment and nothing else. See README.md for the full
environment variable table.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field

from dotenv import load_dotenv

# Loads a local .env file if one is present. Does nothing in an environment
# where the variables are already set, for example Docker Compose.
load_dotenv()


def _env(name: str, default: str | None = None) -> str | None:
    return os.environ.get(name, default)


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    return int(raw) if raw else default


@dataclass(frozen=True)
class PostgresSettings:
    """Connection settings for the operational database.

    The ETL connects with a read-only role, per docs/contracts/database-schema.sql
    (`analytics_reader`). It never writes to Postgres.
    """

    host: str = field(default_factory=lambda: _env("PG_HOST", "localhost"))
    port: int = field(default_factory=lambda: _env_int("PG_PORT", 5432))
    database: str = field(default_factory=lambda: _env("PG_DATABASE", "trading"))
    user: str = field(default_factory=lambda: _env("PG_USER", "analytics_reader"))
    password: str = field(default_factory=lambda: _env("PG_PASSWORD", ""))

    @property
    def sqlalchemy_url(self) -> str:
        return (
            f"postgresql+psycopg://{self.user}:{self.password}"
            f"@{self.host}:{self.port}/{self.database}"
        )


@dataclass(frozen=True)
class FauxnanceSettings:
    """Connection settings for the Fauxnance API. See docs/DECISIONS.md, decision 2."""

    base_url: str = field(
        default_factory=lambda: _env(
            "FAUXNANCE_BASE_URL",
            "https://y4t9nq2bqf.execute-api.eu-west-2.amazonaws.com/v1",
        ).rstrip("/")
    )
    api_key: str | None = field(default_factory=lambda: _env("FAUXNANCE_API_KEY"))
    timeout_seconds: float = field(
        default_factory=lambda: float(_env("FAUXNANCE_TIMEOUT_SECONDS", "10"))
    )
    max_retries: int = field(default_factory=lambda: _env_int("FAUXNANCE_MAX_RETRIES", 4))


@dataclass(frozen=True)
class WarehouseSettings:
    """Connection settings for the analytical store.

    DuckDB is the Snowflake stand-in, per docs/DECISIONS.md, resolved
    contradiction on Snowflake against a flat file. One file, no server.
    """

    path: str = field(default_factory=lambda: _env("DUCKDB_PATH", "warehouse.duckdb"))


@dataclass(frozen=True)
class KafkaSettings:
    """Connection settings for the Sprint 7 event backbone. See docs/contracts/kafka-topics.md."""

    bootstrap_servers: str = field(
        default_factory=lambda: _env("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
    )
    trade_events_topic: str = field(
        default_factory=lambda: _env("KAFKA_TRADE_EVENTS_TOPIC", "trade-events")
    )
    consumer_group: str = field(
        default_factory=lambda: _env("KAFKA_CONSUMER_GROUP", "analytics-loader")
    )


@dataclass(frozen=True)
class Settings:
    postgres: PostgresSettings = field(default_factory=PostgresSettings)
    fauxnance: FauxnanceSettings = field(default_factory=FauxnanceSettings)
    warehouse: WarehouseSettings = field(default_factory=WarehouseSettings)
    kafka: KafkaSettings = field(default_factory=KafkaSettings)


def get_settings() -> Settings:
    """Build settings from the current environment.

    Called at the start of each CLI command rather than once at import time,
    so that tests can set environment variables per case without import-order
    surprises.
    """
    return Settings()

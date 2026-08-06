"""Command-line entry points: `etl`, `dashboard`, `kafka-sink`.

Kept as plain argparse. This is training material, and a contributor reading
the pipeline for the first time should not need to learn a CLI framework to
follow what each command does.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from dataclasses import asdict
from datetime import date

from analytics.config import get_settings

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger("analytics.cli")


def _print_summary(title: str, summary) -> None:
    print(f"\n{title}")
    print(json.dumps(asdict(summary), indent=2, default=str))


def etl_main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="etl", description="Batch ETL: Postgres and Fauxnance into DuckDB.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("run", help="Incremental load of everything created since the watermark.")

    subparsers.add_parser(
        "validate", help="Post-load checks and a reconciliation against Postgres."
    )

    backfill_parser = subparsers.add_parser("backfill", help="Reload a specific date range.")
    backfill_parser.add_argument("--from", dest="from_date", required=True, type=date.fromisoformat)
    backfill_parser.add_argument("--to", dest="to_date", required=True, type=date.fromisoformat)

    args = parser.parse_args(argv)
    settings = get_settings()

    from analytics.etl import pipeline

    if args.command == "run":
        summary = pipeline.run(settings)
        _print_summary("etl run summary", summary)
        return 1 if summary.trades_quarantined and summary.trades_loaded == 0 else 0

    if args.command == "backfill":
        summary = pipeline.backfill(settings, args.from_date, args.to_date)
        _print_summary("etl backfill summary", summary)
        return 0

    if args.command == "validate":
        report = pipeline.validate_warehouse(settings)
        print("\netl validate report")
        print(json.dumps(report, indent=2, default=str))
        ok = (
            all(v == 0 for v in report["nulls"].values())
            and all(v == 0 for v in report["orphan_fact_rows"].values())
            and report["duplicate_current_accounts"] == 0
            and (report["reconciliation"] or {}).get("matches", True)
        )
        return 0 if ok else 1

    parser.print_help()
    return 2


def dashboard_main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="dashboard", description="Build the Sprint 4 HTML report.")
    parser.add_argument("build", nargs="?", default="build", help=argparse.SUPPRESS)
    parser.add_argument(
        "--output", default="report.html", help="Path to write the self-contained HTML report."
    )
    args = parser.parse_args(argv)

    settings = get_settings()
    from analytics.dashboard.report import build_report

    output_path = build_report(settings.warehouse.path, args.output)
    print(f"Wrote {output_path}")
    return 0


def kafka_sink_main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="kafka-sink", description="Consume trade-events into fact_trades."
    )
    parser.add_argument(
        "run", nargs="?", default="run", help=argparse.SUPPRESS
    )
    parser.add_argument(
        "--max-messages",
        type=int,
        default=None,
        help="Stop after this many messages. Omit to run until interrupted.",
    )
    args = parser.parse_args(argv)

    settings = get_settings()
    from analytics.kafka_sink.consumer import run_consumer

    run_consumer(settings, max_messages=args.max_messages)
    return 0


if __name__ == "__main__":
    sys.exit(etl_main())

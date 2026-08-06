"""Assembles the Sprint 4 HTML report: one self-contained file, plotly.js
inlined once, no CDN and no external asset. Opens correctly with no network
connection, which matters because the report is handed to a reader who is
not necessarily near the pipeline that built it.
"""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

import plotly.offline as pyo

from analytics.dashboard import palette
from analytics.dashboard.insights import Insight, build_all_insights
from analytics.db.warehouse import connect

_PAGE_TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Enterprise Trading Platform: analytics report</title>
<style>
  body {{
    margin: 0;
    background: #f9f9f7;
    color: {text_primary};
    font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
  }}
  header {{
    padding: 32px 40px 20px;
    border-bottom: 1px solid {gridline};
    background: {surface};
  }}
  header h1 {{ margin: 0 0 6px; font-size: 22px; }}
  header p {{ margin: 0; color: {text_secondary}; font-size: 14px; }}
  main {{ max-width: 980px; margin: 0 auto; padding: 24px 40px 60px; }}
  section.insight {{
    background: {surface};
    border: 1px solid {gridline};
    border-radius: 10px;
    padding: 20px 24px 8px;
    margin-bottom: 28px;
  }}
  section.insight p.commentary {{
    color: {text_secondary};
    font-size: 14px;
    margin: -6px 0 12px;
    max-width: 70ch;
  }}
  footer {{
    max-width: 980px;
    margin: 0 auto;
    padding: 0 40px 40px;
    color: {text_muted};
    font-size: 12px;
  }}
</style>
<script type="text/javascript">{plotly_js}</script>
</head>
<body>
<header>
  <h1>Enterprise Trading Platform: analytics report</h1>
  <p>Generated {generated_at} from {row_count} rows in fact_trades. Sprint 4 deliverable, star schema per docs/contracts/analytics-schema.sql.</p>
</header>
<main>
{sections}
</main>
<footer>
  Batch load only. A production build of this report also reflects the Sprint 7 Kafka sink; see README.md.
</footer>
</body>
</html>
"""

_SECTION_TEMPLATE = """<section class="insight" id="{slug}">
  <p class="commentary">{commentary}</p>
  {chart_html}
</section>
"""


def _render_insight(insight: Insight, include_plotlyjs_once: list[bool]) -> str:
    chart_html = insight.figure.to_html(
        full_html=False,
        include_plotlyjs=False,
        config={"displaylogo": False, "responsive": True},
    )
    return _SECTION_TEMPLATE.format(
        slug=insight.slug,
        commentary=insight.commentary,
        chart_html=chart_html,
    )


def render_html(insights: list[Insight], row_count: int) -> str:
    plotly_js = pyo.get_plotlyjs()
    sections = "\n".join(_render_insight(i, []) for i in insights)
    return _PAGE_TEMPLATE.format(
        plotly_js=plotly_js,
        sections=sections,
        generated_at=datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        row_count=row_count,
        text_primary=palette.TEXT_PRIMARY,
        text_secondary=palette.TEXT_SECONDARY,
        text_muted=palette.TEXT_MUTED,
        gridline=palette.GRIDLINE,
        surface=palette.SURFACE,
    )


def build_report(warehouse_path: str, output_path: str) -> Path:
    conn = connect(warehouse_path)
    try:
        insights = build_all_insights(conn)
        row_count = conn.execute("SELECT COUNT(*) FROM fact_trades").fetchone()[0]
    finally:
        conn.close()

    html = render_html(insights, row_count)
    out = Path(output_path)
    out.write_text(html, encoding="utf-8")
    return out

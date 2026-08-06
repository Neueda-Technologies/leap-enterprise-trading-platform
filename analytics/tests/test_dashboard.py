from __future__ import annotations

import plotly.graph_objects as go

from analytics.dashboard.insights import build_all_insights
from analytics.dashboard.report import build_report, render_html
from analytics.etl.load import load_fact_trades
from analytics.etl.transform import transform_trades
from analytics.etl.validate import validate_trades
from factories import make_orders_raw


def _load_sample_trades(conn):
    rows = []
    accounts = [1, 1, 1, 2, 3, 4, 5]
    symbols = ["AAPL", "AAPL", "MSFT", "GOOGL", "SPY", "TSLA", "AAPL"]
    sides = ["BUY", "SELL", "BUY", "BUY", "SELL", "BUY", "SELL"]
    statuses = ["FILLED", "FILLED", "REJECTED", "FILLED", "FILLED", "NEW", "FILLED"]
    for i, (acct, sym, side, status) in enumerate(zip(accounts, symbols, sides, statuses)):
        rows.append(
            {
                "account_id": acct,
                "symbol": sym,
                "side": side,
                "status": status,
                "quantity": 10 + i,
                "price": 100.0 + i,
                "executed_price": 100.0 + i if status == "FILLED" else None,
            }
        )
    raw = make_orders_raw(rows)
    trades = transform_trades(raw)

    dim_account = conn.execute("SELECT account_key, source_id, is_current FROM dim_account").df()
    dim_instrument = conn.execute("SELECT instrument_key, symbol FROM dim_instrument").df()
    dim_date = conn.execute("SELECT date_key FROM dim_date").df()

    result = validate_trades(trades, dim_account, dim_instrument, dim_date)
    load_fact_trades(conn, result.valid)
    return result.valid


class TestBuildAllInsights:
    def test_returns_six_insights_with_findings(self, seeded_warehouse):
        _load_sample_trades(seeded_warehouse)
        insights = build_all_insights(seeded_warehouse)
        assert len(insights) == 6
        for insight in insights:
            assert isinstance(insight.finding, str) and insight.finding
            assert isinstance(insight.figure, go.Figure)

    def test_empty_warehouse_still_returns_six_insights_without_crashing(self, seeded_warehouse):
        insights = build_all_insights(seeded_warehouse)
        assert len(insights) == 6
        for insight in insights:
            assert insight.finding

    def test_buy_sell_ratio_matches_the_loaded_data(self, seeded_warehouse):
        _load_sample_trades(seeded_warehouse)
        insights = {i.slug: i for i in build_all_insights(seeded_warehouse)}
        table = insights["buy-sell-ratio"].table
        counts = dict(zip(table["side"], table["order_count"]))
        assert counts["BUY"] == 4
        assert counts["SELL"] == 3

    def test_fill_rate_excludes_rejected_and_new_from_filled_count(self, seeded_warehouse):
        _load_sample_trades(seeded_warehouse)
        insights = {i.slug: i for i in build_all_insights(seeded_warehouse)}
        table = insights["fill-rate"].table
        assert table["orders_filled"].sum() == 5  # 7 orders, 1 REJECTED, 1 NEW
        assert table["orders_placed"].sum() == 7


class TestRenderHtml:
    def test_self_contained_no_external_script_or_stylesheet_tags(self, seeded_warehouse):
        _load_sample_trades(seeded_warehouse)
        insights = build_all_insights(seeded_warehouse)
        html = render_html(insights, row_count=7)
        # The page must not fetch anything over the network to render: no
        # externally-sourced <script> or <link>, and the header/footer text
        # (outside plotly's own embedded JS bundle) carries no bare URL.
        assert '<script src="http' not in html
        assert "<link " not in html
        chrome_only = html.split("<script")[0] + html.rsplit("</script>", 1)[-1]
        assert "http://" not in chrome_only
        assert "https://" not in chrome_only

    def test_every_finding_appears_in_the_page(self, seeded_warehouse):
        _load_sample_trades(seeded_warehouse)
        insights = build_all_insights(seeded_warehouse)
        html = render_html(insights, row_count=7)
        for insight in insights:
            assert insight.finding in html


class TestBuildReport:
    def test_writes_a_report_file(self, seeded_warehouse, tmp_path):
        _load_sample_trades(seeded_warehouse)
        seeded_warehouse.close()  # build_report opens its own connection

        # seeded_warehouse fixture's underlying file path is reused here by
        # re-deriving it from the connection's tmp_path fixture indirectly:
        # simpler to just build straight from the same tmp_path warehouse file.
        output = tmp_path / "report.html"
        db_path = [f for f in tmp_path.iterdir() if f.suffix == ".duckdb"][0]
        result_path = build_report(str(db_path), str(output))
        assert result_path.exists()
        content = result_path.read_text(encoding="utf-8")
        assert "Enterprise Trading Platform" in content

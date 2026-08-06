"""The six business insights the Sprint 4 report ships with.

Every function here reads the star schema only, per the operational and
analytical split in docs/ARCHITECTURE.md: the dashboard never touches
Postgres. Each function returns an `Insight`: a finding stated as a business
claim, a chart that supports it, and the aggregated table behind the chart,
so a reader who distrusts the chart can check the numbers.
"""

from __future__ import annotations

from dataclasses import dataclass

import duckdb
import pandas as pd
import plotly.graph_objects as go

from analytics.dashboard import palette

_LAYOUT_DEFAULTS = dict(
    font=dict(family="system-ui, -apple-system, 'Segoe UI', sans-serif", color=palette.TEXT_PRIMARY),
    plot_bgcolor=palette.SURFACE,
    paper_bgcolor=palette.SURFACE,
    margin=dict(l=60, r=30, t=70, b=50),
)


@dataclass(frozen=True)
class Insight:
    slug: str
    finding: str
    commentary: str
    figure: go.Figure
    table: pd.DataFrame


def _style(fig: go.Figure, title: str) -> go.Figure:
    fig.update_layout(
        title=dict(text=title, font=dict(size=17, color=palette.TEXT_PRIMARY)),
        **_LAYOUT_DEFAULTS,
    )
    fig.update_xaxes(showgrid=False, linecolor=palette.GRIDLINE, tickfont=dict(color=palette.TEXT_MUTED))
    fig.update_yaxes(
        showgrid=True, gridcolor=palette.GRIDLINE, zeroline=False, tickfont=dict(color=palette.TEXT_MUTED)
    )
    return fig


def _empty_insight(slug: str, finding: str, commentary: str) -> Insight:
    fig = go.Figure()
    fig.add_annotation(
        text="No data loaded for this window yet.",
        showarrow=False,
        font=dict(size=14, color=palette.TEXT_MUTED),
    )
    _style(fig, finding)
    return Insight(slug=slug, finding=finding, commentary=commentary, figure=fig, table=pd.DataFrame())


def daily_trade_volume_trend(conn: duckdb.DuckDBPyConnection) -> Insight:
    df = conn.execute(
        """
        SELECT d.full_date AS trade_date, COUNT(*) AS order_count, SUM(f.trade_value) AS total_value
        FROM fact_trades f JOIN dim_date d ON d.date_key = f.date_key
        GROUP BY d.full_date
        ORDER BY d.full_date
        """
    ).df()

    if df.empty:
        return _empty_insight(
            "daily-volume",
            "Daily trade volume trend",
            "Count and summed trade value by day, the first question any desk asks a warehouse.",
        )

    midpoint = len(df) // 2 or 1
    first_half_avg = df["order_count"].iloc[:midpoint].mean()
    second_half_avg = df["order_count"].iloc[midpoint:].mean() if len(df) > midpoint else first_half_avg
    if first_half_avg and first_half_avg > 0:
        change_pct = (second_half_avg - first_half_avg) / first_half_avg * 100
    else:
        change_pct = 0.0

    if len(df) < 4:
        finding = f"Daily order volume averages {df['order_count'].mean():.0f} orders across the loaded window"
    elif change_pct >= 5:
        finding = f"Daily order volume grew {change_pct:.0f} percent from the first half of the window to the second"
    elif change_pct <= -5:
        finding = f"Daily order volume fell {abs(change_pct):.0f} percent from the first half of the window to the second"
    else:
        finding = "Daily order volume holds steady across the loaded window"

    fig = go.Figure()
    fig.add_trace(
        go.Scatter(
            x=df["trade_date"],
            y=df["order_count"],
            mode="lines",
            line=dict(color=palette.SEQUENTIAL, width=2, shape="spline", smoothing=0.3),
            fill="tozeroy",
            fillcolor="rgba(42, 120, 214, 0.12)",
            hovertemplate="%{x|%d %b %Y}<br>%{y} orders<extra></extra>",
            name="Orders placed",
        )
    )
    fig.update_yaxes(title_text="Orders placed per day")
    fig.update_xaxes(title_text="Date")
    _style(fig, finding)

    return Insight(
        slug="daily-volume",
        finding=finding,
        commentary="Count and summed trade value by day. Weekday clustering is expected: dim_date.is_weekday explains a five-day sawtooth without it being misread as a trend.",
        figure=fig,
        table=df,
    )


def most_active_accounts(conn: duckdb.DuckDBPyConnection) -> Insight:
    df = conn.execute(
        """
        SELECT a.account_id, a.holder_name, COUNT(*) AS order_count
        FROM fact_trades f
        JOIN dim_account a ON a.account_key = f.account_key AND a.is_current
        GROUP BY a.account_id, a.holder_name
        ORDER BY order_count DESC
        """
    ).df()

    if df.empty:
        return _empty_insight(
            "active-accounts",
            "Most active accounts",
            "Order count by account, current version only.",
        )

    total = df["order_count"].sum()
    top_n = min(3, len(df))
    top_share = df["order_count"].iloc[:top_n].sum() / total * 100 if total else 0
    finding = f"The top {top_n} account{'s' if top_n != 1 else ''} generate{'s' if top_n == 1 else ''} {top_share:.0f} percent of order flow"

    display = df.head(10).iloc[::-1]
    colours = palette.categorical(min(len(display), 8))
    colours = (colours * (len(display) // len(colours) + 1))[: len(display)] if colours else []

    fig = go.Figure()
    fig.add_trace(
        go.Bar(
            x=display["order_count"],
            y=display["holder_name"] + " (" + display["account_id"] + ")",
            orientation="h",
            marker_color=colours if colours else palette.SEQUENTIAL,
            text=display["order_count"],
            textposition="outside",
            hovertemplate="%{y}<br>%{x} orders<extra></extra>",
        )
    )
    fig.update_xaxes(title_text="Orders placed")
    fig.update_yaxes(title_text="")
    _style(fig, finding)

    return Insight(
        slug="active-accounts",
        finding=finding,
        commentary="Ranks dim_account rows where is_current is true, so a closed or superseded account version never inflates the count.",
        figure=fig,
        table=df,
    )


def fill_rate(conn: duckdb.DuckDBPyConnection) -> Insight:
    df = conn.execute(
        """
        SELECT d.year, d.month,
               COUNT(*) AS orders_placed,
               SUM(CASE WHEN f.status = 'FILLED' THEN 1 ELSE 0 END) AS orders_filled,
               SUM(CASE WHEN f.status = 'FILLED' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS fill_rate_pct
        FROM fact_trades f
        JOIN dim_date d ON d.date_key = f.date_key
        GROUP BY d.year, d.month
        ORDER BY d.year, d.month
        """
    ).df()

    if df.empty:
        return _empty_insight(
            "fill-rate",
            "Fill rate",
            "Filled orders as a share of every order placed, including rejects and cancels.",
        )

    df["period"] = df["year"].astype(str) + "-" + df["month"].astype(str).str.zfill(2)
    overall = df["orders_filled"].sum() / df["orders_placed"].sum() * 100
    finding = f"{overall:.0f} percent of orders placed end up filled"

    fig = go.Figure()
    fig.add_trace(
        go.Bar(
            x=df["period"],
            y=df["fill_rate_pct"],
            marker_color=palette.SEQUENTIAL,
            text=[f"{v:.0f}%" for v in df["fill_rate_pct"]],
            textposition="outside",
            hovertemplate="%{x}<br>%{y:.1f}%% filled<extra></extra>",
        )
    )
    fig.add_hline(
        y=overall, line_dash="dot", line_color=palette.TEXT_MUTED,
        annotation_text=f"Average {overall:.0f}%", annotation_font_color=palette.TEXT_SECONDARY,
    )
    fig.update_yaxes(title_text="Fill rate (%)", range=[0, 105])
    fig.update_xaxes(title_text="Month")
    _style(fig, finding)

    return Insight(
        slug="fill-rate",
        finding=finding,
        commentary="Rejected and cancelled orders are loaded into fact_trades precisely so this figure is answerable: a warehouse holding only fills would report 100 percent every month.",
        figure=fig,
        table=df,
    )


def exposure_by_instrument(conn: duckdb.DuckDBPyConnection) -> Insight:
    df = conn.execute(
        """
        SELECT i.symbol, f.side, SUM(f.trade_value) AS exposure
        FROM fact_trades f
        JOIN dim_instrument i ON i.instrument_key = f.instrument_key
        GROUP BY i.symbol, f.side
        ORDER BY exposure DESC
        """
    ).df()

    if df.empty:
        return _empty_insight(
            "exposure",
            "Exposure by instrument",
            "Summed trade value by instrument and side.",
        )

    totals = df.groupby("symbol")["exposure"].sum().sort_values(ascending=False)
    top_symbol = totals.index[0]
    top_share = totals.iloc[0] / totals.sum() * 100 if totals.sum() else 0
    finding = f"{top_symbol} accounts for {top_share:.0f} percent of total exposure"

    ordered_symbols = list(totals.index)
    fig = go.Figure()
    for side, colour in (("BUY", palette.BUY), ("SELL", palette.SELL)):
        side_df = df[df["side"] == side].set_index("symbol").reindex(ordered_symbols).fillna(0)
        fig.add_trace(
            go.Bar(
                x=ordered_symbols,
                y=side_df["exposure"],
                name=side,
                marker_color=colour,
                hovertemplate="%{x}<br>" + side + " $%{y:,.0f}<extra></extra>",
            )
        )
    fig.update_layout(barmode="group", legend=dict(orientation="h", y=1.12, x=0))
    fig.update_yaxes(title_text="Trade value ($)")
    fig.update_xaxes(title_text="Instrument")
    _style(fig, finding)

    return Insight(
        slug="exposure",
        finding=finding,
        commentary="Summed trade_value, never summed price: price is not additive across rows, only the derived value column is.",
        figure=fig,
        table=df,
    )


def average_trade_size(conn: duckdb.DuckDBPyConnection) -> Insight:
    df = conn.execute(
        """
        SELECT d.year, d.month, AVG(f.trade_value) AS avg_trade_value, COUNT(*) AS order_count
        FROM fact_trades f
        JOIN dim_date d ON d.date_key = f.date_key
        GROUP BY d.year, d.month
        ORDER BY d.year, d.month
        """
    ).df()

    if df.empty:
        return _empty_insight(
            "avg-trade-size",
            "Average trade size",
            "Average trade_value over the loaded window.",
        )

    df["period"] = df["year"].astype(str) + "-" + df["month"].astype(str).str.zfill(2)
    overall_avg = (df["avg_trade_value"] * df["order_count"]).sum() / df["order_count"].sum()
    finding = f"The average order is worth ${overall_avg:,.0f}"

    fig = go.Figure()
    fig.add_trace(
        go.Bar(
            x=df["period"],
            y=df["avg_trade_value"],
            marker_color=palette.SEQUENTIAL,
            hovertemplate="%{x}<br>avg $%{y:,.0f}<extra></extra>",
        )
    )
    fig.update_yaxes(title_text="Average trade value ($)")
    fig.update_xaxes(title_text="Month")
    _style(fig, finding)

    return Insight(
        slug="avg-trade-size",
        finding=finding,
        commentary="Averages trade_value, which is already quantity multiplied by price. Averaging price alone would treat a 10-share order and a 10,000-share order as equally sized.",
        figure=fig,
        table=df,
    )


def buy_sell_ratio(conn: duckdb.DuckDBPyConnection) -> Insight:
    df = conn.execute(
        """
        SELECT side, COUNT(*) AS order_count
        FROM fact_trades
        GROUP BY side
        ORDER BY side
        """
    ).df()

    if df.empty:
        return _empty_insight(
            "buy-sell-ratio",
            "Buy and sell balance",
            "Order count split by side.",
        )

    counts = dict(zip(df["side"], df["order_count"]))
    buys = counts.get("BUY", 0)
    sells = counts.get("SELL", 0)
    total = buys + sells
    buy_pct = buys / total * 100 if total else 0
    finding = f"Buy orders make up {buy_pct:.0f} percent of order flow"

    fig = go.Figure()
    fig.add_trace(
        go.Bar(
            x=["BUY", "SELL"],
            y=[buys, sells],
            marker_color=[palette.BUY, palette.SELL],
            text=[buys, sells],
            textposition="outside",
            hovertemplate="%{x}<br>%{y} orders<extra></extra>",
        )
    )
    fig.update_yaxes(title_text="Orders placed")
    fig.update_xaxes(title_text="")
    _style(fig, finding)

    return Insight(
        slug="buy-sell-ratio",
        finding=finding,
        commentary="A ratio skewed toward one side over a long window is usually a strategy signature, not noise, and is worth cross-checking against the account breakdown above.",
        figure=fig,
        table=df,
    )


def build_all_insights(conn: duckdb.DuckDBPyConnection) -> list[Insight]:
    return [
        daily_trade_volume_trend(conn),
        most_active_accounts(conn),
        fill_rate(conn),
        exposure_by_instrument(conn),
        average_trade_size(conn),
        buy_sell_ratio(conn),
    ]

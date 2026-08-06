"""Chart colours.

Fixed categorical order, not cycled and not chosen per chart. Values are the
validated default palette (colourblind-safe adjacent pairs in both light and
dark mode). A ninth series would fold into "Other" rather than extend this
list; nothing in this report needs more than eight.
"""

from __future__ import annotations

CATEGORICAL = [
    "#2a78d6",  # 1 blue
    "#eb6834",  # 2 orange
    "#1baf7a",  # 3 aqua
    "#eda100",  # 4 yellow
    "#e87ba4",  # 5 magenta
    "#008300",  # 6 green
    "#4a3aa7",  # 7 violet
    "#e34948",  # 8 red
]

# Semantic, not arbitrary: BUY takes the first categorical slot, SELL the
# second, and that assignment is used everywhere a chart splits by side so a
# reader learns the colour once.
BUY = CATEGORICAL[0]
SELL = CATEGORICAL[1]

# Sequential single hue for a single, unbroken series (a trend line with
# nothing to compare it against).
SEQUENTIAL = CATEGORICAL[0]

TEXT_PRIMARY = "#0b0b0b"
TEXT_SECONDARY = "#52514e"
TEXT_MUTED = "#898781"
GRIDLINE = "#e1e0d9"
SURFACE = "#fcfcfb"


def categorical(n: int) -> list[str]:
    """The first `n` categorical slots, in fixed order. Raises past eight
    rather than generating a new hue, per the fold-to-Other rule.
    """
    if n > len(CATEGORICAL):
        raise ValueError(f"only {len(CATEGORICAL)} categorical slots are defined, requested {n}")
    return CATEGORICAL[:n]

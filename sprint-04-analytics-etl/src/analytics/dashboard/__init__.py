"""The dashboard: charts, and the file you hand to a reader.

Responsibility: read the analytical store, produce one chart per claim, and
write them into an artefact somebody can open. Nothing here calls Fauxnance
and nothing here cleans data. If a chart needs a number the store does not
hold, the number belongs in the transform.

Write a self-contained file. plotly can inline its own JavaScript, so an HTML
report opens on a laptop with no network and no build step. A dashboard that
only exists while a notebook kernel is running cannot be reviewed, and a chart
that loads its library from a content delivery network is a blank page on a
locked-down machine.

Every chart is committed and named in `claims.md`, because the claim and the
chart are assessed together.
"""

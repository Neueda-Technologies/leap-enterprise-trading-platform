"""Extract: pull raw candles and put them somewhere they can be pulled again.

Responsibility: for each symbol in scope, obtain the raw response envelope for
a date range and hand it on unchanged. Nothing here reshapes, cleans, filters
or aggregates. The moment this module starts computing a return, the transform
tests stop covering the thing that computed it.

Cache to disk. One symbol over one range is one request against a quota of
2000 per day per key, shared with everything else you build this week, and a
team debugging a chart will run the pipeline twenty times before lunch. Write
the raw envelope to a file keyed by symbol and range, read it back when it is
already there, and re-runs cost nothing. Cache the raw response rather than
the cleaned frame, so that a change to the transform does not need a fresh
pull to test.

`.cache/` in this folder is git-ignored and is the obvious place. Do not
commit a cache: it is not a fixture, and a stale one that disagrees with the
API is worse than no cache.
"""

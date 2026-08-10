"""The request budget.

Single responsibility: count requests, and answer whether another one is
allowed. It makes no request itself.

2000 requests per day per key, resetting at 00:00 UTC, and the key is shared.
The Trade Executor prices every fill against it, and from Sprint 10 the
Portfolio extension prices every valuation against it. A poller that spends the
whole quota leaves nothing for either, and the first symptom is orders being
rejected because no price could be obtained.

So the budget is the poller's share rather than the whole allowance, and it is
configuration rather than a constant. When the share is spent the poller stops
calling until the reset, and says so once rather than on every cycle.

Two things are worth getting right and are easy to get wrong. The reset is at
midnight UTC and not at midnight where you are. A budget held only in memory
starts again at zero when the container restarts, which is defensible for a
teaching platform as long as you know it and say so.
"""

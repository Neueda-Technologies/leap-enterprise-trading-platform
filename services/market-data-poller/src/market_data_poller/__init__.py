"""Market-data poller.

Fauxnance has no stream. This package is what makes one exist: it polls the batch quotes endpoint
on an interval and publishes each quote onto the ``market-data`` topic.
"""

__version__ = "1.0.0"

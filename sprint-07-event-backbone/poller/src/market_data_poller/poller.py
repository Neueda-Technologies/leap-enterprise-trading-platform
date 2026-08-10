"""The poll loop: batching, the interval, and staying alive.

Single responsibility: split the symbol list into groups of at most 25, ask the
client for each group, hand every quote to the publisher, sleep the remainder
of the interval, repeat.

The batch limit of 25 is the endpoint's, not a preference. Splitting is what
turns a request per symbol into a request per 25 symbols, and it is the
difference between a key that lasts a day and a key that is gone before lunch.

A market-data feed that exits is worse than one that is wrong, because a dead
process is silent. One bad symbol does not stop the batch. One failed batch does
not stop the cycle. One failed cycle does not stop the loop. Anything
unforeseen is caught at the top of the loop, logged with its stack trace, and
the loop continues.

Shutdown is part of the deliverable rather than an afterthought. `docker stop`
sends SIGTERM and waits about ten seconds before killing the container, so a
process that ignores the signal is killed part way through a publish. Finish the
cycle, flush the producer, exit. Have every sleep in the service wait on the
same shutdown signal, or a stop takes as long as the longest interval.

Sleeping the remainder of the interval is not the same as sleeping the
interval. A cycle that takes four seconds followed by a thirty second sleep is
a thirty-four second cycle, and the drift compounds over a taught day.
"""

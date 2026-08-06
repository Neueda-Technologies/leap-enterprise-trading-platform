package com.neueda.trading.executor.execution;

import java.time.Duration;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Holds the consumer thread for a randomised interval before the fill is decided.
 *
 * <p>Fauxnance answers in tens of milliseconds and Postgres answers in single milliseconds, so
 * without this the blotter reaches FILLED before the operator has let go of the mouse button. That
 * makes a demo look like the synchronous Sprint 6 behaviour and hides the property Sprint 7 exists
 * to teach. The delay is bounded well inside {@code max.poll.interval.ms}, so it does not provoke a
 * rebalance.
 *
 * <p>Set both bounds to zero to switch it off.
 */
public class ExecutionLatency {

    private final long minMillis;
    private final long maxMillis;

    public ExecutionLatency(Duration min, Duration max) {
        this.minMillis = Math.max(0, min.toMillis());
        this.maxMillis = Math.max(this.minMillis, max.toMillis());
    }

    public void pause() {
        if (maxMillis == 0) {
            return;
        }
        long millis = minMillis == maxMillis
                ? minMillis
                : ThreadLocalRandom.current().nextLong(minMillis, maxMillis + 1);
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while simulating execution latency", e);
        }
    }
}

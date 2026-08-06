package com.neueda.trading.executor.config;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Everything about executor behaviour that an instructor or a participant may want to change
 * without recompiling. Bound from the {@code executor.*} block of {@code application.yml}.
 */
@ConfigurationProperties(prefix = "executor")
public class ExecutorProperties {

    private Topics topics = new Topics();
    private Latency latency = new Latency();
    private OptimisticLock optimisticLock = new OptimisticLock();

    /**
     * Total delivery attempts for one message before it goes to the dead-letter topic. Counts the
     * first attempt, so 4 means one attempt plus three retries.
     */
    private int maxDeliveryAttempts = 4;

    public Topics getTopics() {
        return topics;
    }

    public void setTopics(Topics topics) {
        this.topics = topics;
    }

    public Latency getLatency() {
        return latency;
    }

    public void setLatency(Latency latency) {
        this.latency = latency;
    }

    public OptimisticLock getOptimisticLock() {
        return optimisticLock;
    }

    public void setOptimisticLock(OptimisticLock optimisticLock) {
        this.optimisticLock = optimisticLock;
    }

    public int getMaxDeliveryAttempts() {
        return maxDeliveryAttempts;
    }

    public void setMaxDeliveryAttempts(int maxDeliveryAttempts) {
        this.maxDeliveryAttempts = maxDeliveryAttempts;
    }

    public static class Topics {

        private String orders = "orders";
        private String tradeEvents = "trade-events";

        /**
         * Suffix appended to the source topic name to build the dead-letter topic, per
         * {@code docs/contracts/kafka-topics.md}. Spring's default suffix is {@code -dlt}, which
         * the contract does not use.
         */
        private String deadLetterSuffix = ".DLT";

        public String getOrders() {
            return orders;
        }

        public void setOrders(String orders) {
            this.orders = orders;
        }

        public String getTradeEvents() {
            return tradeEvents;
        }

        public void setTradeEvents(String tradeEvents) {
            this.tradeEvents = tradeEvents;
        }

        public String getDeadLetterSuffix() {
            return deadLetterSuffix;
        }

        public void setDeadLetterSuffix(String deadLetterSuffix) {
            this.deadLetterSuffix = deadLetterSuffix;
        }
    }

    /**
     * Simulated execution latency. Real venues take time to fill an order, and a demo in which the
     * blotter flips to FILLED before the operator releases the mouse button hides the asynchrony
     * Sprint 7 exists to teach. Set both bounds to zero to switch it off in an integration test.
     */
    public static class Latency {

        private Duration min = Duration.ofMillis(250);
        private Duration max = Duration.ofMillis(750);

        public Duration getMin() {
            return min;
        }

        public void setMin(Duration min) {
            this.min = min;
        }

        public Duration getMax() {
            return max;
        }

        public void setMax(Duration max) {
            this.max = max;
        }
    }

    /**
     * Retry budget for a lost optimistic lock on {@code accounts.version}. A conflict means another
     * writer won the race, not that anything is broken, so the executor re-reads and tries again.
     */
    public static class OptimisticLock {

        private int maxAttempts = 5;
        private Duration backoff = Duration.ofMillis(25);

        public int getMaxAttempts() {
            return maxAttempts;
        }

        public void setMaxAttempts(int maxAttempts) {
            this.maxAttempts = maxAttempts;
        }

        public Duration getBackoff() {
            return backoff;
        }

        public void setBackoff(Duration backoff) {
            this.backoff = backoff;
        }
    }
}

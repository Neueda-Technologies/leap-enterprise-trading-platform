package com.tradingplatform.domain.model;

/**
 * Lifecycle state of an order.
 *
 * <p>{@code NEW} is the only working state. It is held from acceptance until execution resolves it.
 * The other three are terminal and nothing moves out of them.
 *
 * <p>There is no partial-fill state. That is a deliberate constraint on the platform, not an
 * oversight: an order fills in full or it is rejected, which keeps the position arithmetic and the
 * event schema simple enough to reason about in one sprint.
 */
public enum OrderStatus {

    /** Accepted and recorded, not yet executed. */
    NEW,

    /** Executed in full. Terminal. */
    FILLED,

    /** Refused at execution, for example because the limit price was not met. Terminal. */
    REJECTED,

    /** Withdrawn by the customer before execution. Terminal. */
    CANCELLED;

    /** Returns true when no further transition out of this state is permitted. */
    public boolean isTerminal() {
        return this != NEW;
    }
}

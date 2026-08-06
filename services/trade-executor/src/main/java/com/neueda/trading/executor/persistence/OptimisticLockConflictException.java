package com.neueda.trading.executor.persistence;

/**
 * Thrown when the guarded update of {@code accounts} affects zero rows, meaning another transaction
 * changed the version first. It is not a failure: the executor rolls back, re-reads and tries
 * again. Only an exhausted retry budget is an error.
 */
public class OptimisticLockConflictException extends RuntimeException {

    public OptimisticLockConflictException(long accountId, int expectedVersion) {
        super("Account " + accountId + " was modified by another writer, expected version "
                + expectedVersion);
    }
}

package com.neueda.trading.executor.support;

import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * A transaction template that runs the callback and nothing else.
 *
 * <p>The unit tests mock the repository, so there is no connection to begin a transaction on. What
 * they need from the template is that the callback runs and that a thrown exception propagates,
 * which is what drives the optimistic-lock retry loop. Transactional behaviour itself is checked
 * against a real database, not here.
 */
public final class DirectTransactionTemplate {

    private DirectTransactionTemplate() {
    }

    public static TransactionTemplate create() {
        return new TransactionTemplate(new PlatformTransactionManager() {

            @Override
            public TransactionStatus getTransaction(TransactionDefinition definition) {
                return new SimpleTransactionStatus();
            }

            @Override
            public void commit(TransactionStatus status) {
                // Nothing to commit: the repository is a mock.
            }

            @Override
            public void rollback(TransactionStatus status) {
                // Nothing to roll back.
            }
        });
    }
}

/**
 * Execution: the fill decision and the transaction that follows it.
 *
 * <p>Single responsibility: given an order and a quote, decide fill or reject, and make the
 * database agree with that decision. This is the centre of the sprint and the package a reviewer
 * opens first.
 *
 * <p>The fill decision is pure. Given the same order and the same quote it returns the same answer,
 * and it touches no database and no socket. Written that way it is testable without any
 * infrastructure, which is the only reason the interesting cases get tested at all.
 *
 * <p>The settlement is one transaction over three writes: the order's status, the account's cash,
 * and the position. All three commit or none of them does. An order that is marked filled while the
 * cash movement is rolled back leaves the audit trail disagreeing with the balance, and nothing in
 * the platform reconciles the two for you.
 *
 * <p>The transaction opens with a guarded state transition rather than a read. The difference is
 * the whole sprint: a read followed by a decision followed by a write can be run twice by two
 * deliveries of the same message, and a write conditioned on the state it expects cannot.
 *
 * <p>Business rules 6 and 7 are re-checked here, against the fill price and the balance as they are
 * now. The Trade REST API checked them at acceptance, against a limit price and a balance that have
 * both since moved.
 */
package com.tradingplatform.executor.execution;

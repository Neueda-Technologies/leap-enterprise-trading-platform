/**
 * The Trade Executor: the platform's execution venue.
 *
 * <p>Single responsibility of this service: take an order that the Trade REST API has already
 * accepted and recorded, decide whether it fills and at what price, move the cash and the position
 * to match that decision, and tell the rest of the platform what happened. It is the only component
 * that decides whether an order fills.
 *
 * <p>It accepts nothing from a customer. Everything it acts on arrived on the {@code orders} topic,
 * was validated at acceptance, and has a row in Postgres already. The executor's job starts at the
 * point where the answer stopped being computable inside one HTTP request.
 *
 * <p>The annotated application class belongs here, at the root, so that component scanning reaches
 * every package below it without being configured to.
 *
 * <p>Rename or reorganise these packages if your design says something else, and tell the harness
 * what you chose in {@code manifest.env}.
 */
package com.tradingplatform.executor;

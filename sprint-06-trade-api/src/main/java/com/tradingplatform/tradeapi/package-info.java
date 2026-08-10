/**
 * The Trade REST API: the platform's front door.
 *
 * <p>Single responsibility of this service: accept an order over HTTP, prove the caller is who they
 * claim to be, apply the rules that live in the Sprint 5 domain module, persist the outcome, and
 * answer in the shape {@code contracts/trade-api.yaml} defines. It decides nothing the domain can
 * decide, and it prices nothing.
 *
 * <p>The annotated application class belongs here, at the root, so that component scanning reaches
 * every package below it without being configured to.
 *
 * <p>Rename or reorganise these packages if your design says something else, and tell the harness
 * what you chose in {@code manifest.env}.
 */
package com.tradingplatform.tradeapi;

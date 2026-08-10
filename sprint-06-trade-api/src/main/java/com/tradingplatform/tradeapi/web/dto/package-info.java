/**
 * Request and response types, one per schema in the contract.
 *
 * <p>Single responsibility: carry the JSON shape {@code contracts/trade-api.yaml} defines, and
 * nothing else. These types exist so that the wire format can change without the domain changing,
 * and so that the Angular client generated from the contract in Sprint 9 compiles against what this
 * service actually sends.
 *
 * <p>A DTO holds no behaviour. Serialising a domain entity straight onto the wire looks like less
 * code and publishes every field the entity happens to have, including the ones a customer must not
 * see, and it turns a refactor of the domain into a breaking API change.
 *
 * <p>Two fields in the contract need reading twice. {@code AccountResponse.id} is what every other
 * endpoint calls {@code accountId}, and {@code AccountResponse.accountId} is the string business
 * reference. Getting them the wrong way round compiles.
 */
package com.tradingplatform.tradeapi.web.dto;

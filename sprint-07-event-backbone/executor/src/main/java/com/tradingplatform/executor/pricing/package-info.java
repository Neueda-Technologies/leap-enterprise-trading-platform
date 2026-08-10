/**
 * Pricing: obtaining a quote from the Fauxnance API.
 *
 * <p>Single responsibility: given a symbol, answer with a price or say plainly that there is not
 * one. It applies no fill rule and knows nothing about orders.
 *
 * <p>Two properties of this package are design decisions rather than plumbing, and both are asked
 * about at the review.
 *
 * <p>Which failures cost a retry. A timeout will probably succeed on the next attempt. A 404 for a
 * symbol Fauxnance does not serve will not, and retrying it spends requests to learn the same thing
 * three times. A 429 will not either, because the quota does not refill inside a retry window.
 *
 * <p>What happens to the quota. This service shares one key with the poller and, from Sprint 10,
 * with anything else that prices. Ten orders on one symbol inside a second do not need ten
 * requests.
 *
 * <p>The key is read from {@code FAUXNANCE_API_KEY} and from nowhere else. It is never a literal, a
 * default, or a value in a properties file.
 */
package com.tradingplatform.executor.pricing;

/**
 * The service layer: orchestration and the transaction boundary.
 *
 * <p>Single responsibility: load what the domain needs, call the domain, persist what it decided,
 * and do the persisting inside one transaction so that the work either all happens or none of it
 * does. Cash and position move together or neither moves.
 *
 * <p>This layer takes no servlet type, no request object and no status code. Given those, it can
 * only be called from a controller, and the Sprint 7 executor is the second caller.
 *
 * <p>It is also where authorisation is decided, because this is the first place the account key in
 * the request is known. Whether the caller holds a valid token was answered before any of this ran.
 */
package com.tradingplatform.tradeapi.service;

/**
 * The web layer: HTTP in, HTTP out.
 *
 * <p>Single responsibility: translate between the wire and the service layer. A controller reads a
 * path, a query parameter and a request body, hands typed values to a service, and turns what comes
 * back into a status code and a response body. The exception handling that produces the platform
 * error envelope belongs here too, in one place, because there is one envelope.
 *
 * <p>Nothing in this package contains SQL, opens a transaction, or holds a business rule. A query
 * written in a class that handles requests cannot be tested without a web layer and cannot be
 * reused by the next caller that needs the same rows. It is one of the two violations that fail
 * the review on sight.
 */
package com.tradingplatform.tradeapi.web;

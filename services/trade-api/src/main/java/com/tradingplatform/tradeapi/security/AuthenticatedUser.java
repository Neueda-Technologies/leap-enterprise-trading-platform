package com.tradingplatform.tradeapi.security;

import java.util.List;

/**
 * The identity carried by a verified token.
 *
 * <p>Every field here came out of a token whose signature and expiry were checked. Nothing in this
 * record may ever be populated from a query parameter, a request header the client controls, or a
 * decoded payload that has not been verified. Accepting a client-supplied user identifier is OWASP
 * A01, and it is the single most common way a JWT integration is got wrong.
 *
 * @param subject   the {@code sub} claim, a stable user UUID
 * @param accountId the {@code accountId} claim, the numeric trading account key
 * @param roles     the {@code roles} claim, never empty
 * @param issuer    the {@code iss} claim, {@code auth-stub} or {@code auth-service}
 */
public record AuthenticatedUser(String subject, Long accountId, List<String> roles, String issuer) {

    /** Request attribute the filter stores this under, and controllers read it from. */
    public static final String ATTRIBUTE = "com.tradingplatform.authenticatedUser";

    /** An operator, permitted to address accounts other than their own. */
    public static final String ROLE_ADMIN = "ADMIN";

    /** True when this identity may reach the given account. */
    public boolean canAccess(Long targetAccountId) {
        if (targetAccountId == null) {
            return false;
        }
        return roles.contains(ROLE_ADMIN) || targetAccountId.equals(accountId);
    }
}

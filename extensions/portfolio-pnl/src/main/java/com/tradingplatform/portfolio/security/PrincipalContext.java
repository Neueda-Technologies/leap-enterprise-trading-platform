package com.tradingplatform.portfolio.security;

/**
 * Carries the verified principal for the lifetime of one request. Set by
 * {@link JwtAuthenticationFilter} once the token has been checked, read by
 * controllers that need to compare the token's {@code accountId} claim against the
 * account requested in the path.
 */
public final class PrincipalContext {

    private static final ThreadLocal<AuthenticatedPrincipal> CURRENT = new ThreadLocal<>();

    private PrincipalContext() {
    }

    static void set(AuthenticatedPrincipal principal) {
        CURRENT.set(principal);
    }

    public static AuthenticatedPrincipal get() {
        return CURRENT.get();
    }

    static void clear() {
        CURRENT.remove();
    }
}

package com.tradingplatform.portfolio.security;

import java.util.List;

/**
 * The claims this service cares about from a verified access token, per the claims
 * contract in docs/contracts/auth-api.yaml.
 */
public record AuthenticatedPrincipal(String subject, long accountId, List<String> roles) {
}

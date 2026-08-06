package com.tradingplatform.tradeapi.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.tradingplatform.tradeapi.security.JwtAuthenticationFilter;
import com.tradingplatform.tradeapi.security.JwtVerifier;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;

/**
 * Maps the JWT filter onto the protected routes.
 *
 * <p>The pattern is {@code /api/*}, which covers every versioned route the contract defines and
 * every one added later. Nothing under {@code /api} is reachable without a verified token.
 *
 * <p>Three paths are deliberately outside it. {@code /swagger-ui} and {@code /v3/api-docs} serve the
 * contract, which is public information and which participants need to read before they hold a
 * token. {@code /actuator/health} answers the Docker Compose health check, which has no way to
 * obtain one. In a deployed environment the actuator port is separated from the application port and
 * the management endpoints are not exposed publicly; document that rather than claiming this
 * configuration does it.
 *
 * <p>This service does not use Spring Security. A single filter is enough to demonstrate JWT
 * verification, and Spring Security's defaults, its form login and its own 401 handling would have
 * to be switched off one by one before the platform error envelope came out of a failed
 * authentication. The trade is deliberate and it is worth naming: adding method-level authorisation,
 * CSRF handling or an OAuth2 resource server later means adopting Spring Security, not extending
 * this.
 */
@Configuration
public class SecurityFilterConfig {

    /** The one protected URL pattern. */
    public static final String PROTECTED_PATTERN = "/api/*";

    @Bean
    public FilterRegistrationBean<JwtAuthenticationFilter> jwtAuthenticationFilter(
            JwtVerifier verifier, ObjectMapper objectMapper) {

        FilterRegistrationBean<JwtAuthenticationFilter> registration = new FilterRegistrationBean<>();
        registration.setFilter(new JwtAuthenticationFilter(verifier, objectMapper));
        registration.addUrlPatterns(PROTECTED_PATTERN);
        registration.setName("jwtAuthenticationFilter");
        // Ahead of anything that might log or trace, so an unauthenticated request is refused before
        // the rest of the chain does work on its behalf.
        registration.setOrder(Ordered.HIGHEST_PRECEDENCE + 10);
        return registration;
    }
}

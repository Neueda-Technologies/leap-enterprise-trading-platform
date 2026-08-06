package com.tradingplatform.tradeapi.config;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/**
 * Everything about this service that changes between environments, in one place and validated at
 * startup.
 *
 * <p>Binding configuration to a typed record rather than scattering {@code @Value} annotations has a
 * practical payoff: a missing or malformed value fails the application context, at boot, with the
 * offending property named. The alternative fails on the first request that happens to need it,
 * usually in an environment where nobody is watching.
 *
 * @param executionMode how an accepted order is resolved
 * @param baseCurrency  ISO 4217 code reported on the balance endpoint
 * @param jwt           token verification settings
 * @param kafka         event publishing settings
 */
@Validated
@ConfigurationProperties(prefix = "trading")
public record TradingProperties(

        @NotNull ExecutionMode executionMode,

        @NotBlank @Size(min = 3, max = 3) String baseCurrency,

        @NotNull Jwt jwt,

        @NotNull Kafka kafka) {

    /**
     * JWT verification.
     *
     * @param secret        HS256 signing secret, shared with the auth service. Read from
     *                      {@code JWT_SECRET}. Never commit a production value.
     * @param clockSkew     seconds of tolerance on {@code exp} and {@code iat}, for clocks that
     *                      disagree between containers
     * @param requiredIssuer issuer that tokens must carry, or blank to accept any. Blank by default:
     *                      the auth contract says consumers must not require a particular value, so
     *                      that the Sprint 8 cutover from {@code auth-stub} to {@code auth-service}
     *                      needs no change here.
     */
    public record Jwt(
            @NotBlank @Size(min = 32, message = "JWT_SECRET must be at least 32 characters for HS256")
            String secret,
            long clockSkew,
            String requiredIssuer) {
    }

    /**
     * Event publishing.
     *
     * @param enabled          false runs the service with no broker, which is the Sprint 6 state
     * @param ordersTopic      accepted orders awaiting execution
     * @param tradeEventsTopic order lifecycle outcomes
     */
    public record Kafka(
            boolean enabled,
            @NotBlank String ordersTopic,
            @NotBlank String tradeEventsTopic) {
    }
}

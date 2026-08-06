package com.tradingplatform.tradeapi.security;

import com.tradingplatform.tradeapi.TestData;
import com.tradingplatform.tradeapi.config.ExecutionMode;
import com.tradingplatform.tradeapi.config.TradingProperties;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

/**
 * Token verification, including the paths that are easy to leave open.
 *
 * <p>The wrong-signature and expired-token cases are the ones worth having. A verifier that decodes
 * without verifying passes every happy-path test ever written for it.
 */
@DisplayName("JwtVerifier")
class JwtVerifierTest {

    private static final SecretKey KEY =
            Keys.hmacShaKeyFor(TestData.JWT_SECRET.getBytes(StandardCharsets.UTF_8));
    private static final SecretKey OTHER_KEY = Keys.hmacShaKeyFor(
            "an-entirely-different-secret-of-sufficient-length".getBytes(StandardCharsets.UTF_8));

    private JwtVerifier verifier() {
        return new JwtVerifier(TestData.properties(ExecutionMode.ASYNC));
    }

    private JwtVerifier verifierRequiringIssuer(String issuer) {
        TradingProperties base = TestData.properties(ExecutionMode.ASYNC);
        return new JwtVerifier(new TradingProperties(base.executionMode(), base.baseCurrency(),
                new TradingProperties.Jwt(TestData.JWT_SECRET, 30, issuer), base.kafka()));
    }

    private static String token(SecretKey key,
                                Map<String, Object> claims,
                                Instant issuedAt,
                                Instant expiresAt) {
        return Jwts.builder()
                .subject("8f14e45f-ceea-4c1b-9d3b-1a2b3c4d5e6f")
                .issuer("auth-stub")
                .claims(claims)
                .issuedAt(Date.from(issuedAt))
                .expiration(Date.from(expiresAt))
                .signWith(key)
                .compact();
    }

    private static String validToken() {
        Instant now = Instant.now();
        return token(KEY, Map.of("accountId", 1, "roles", List.of("CUSTOMER")),
                now, now.plus(Duration.ofMinutes(15)));
    }

    @Test
    @DisplayName("a valid token yields the claims contract from auth-api.yaml")
    void testVerify_ValidToken() {
        AuthenticatedUser user = verifier().verify(validToken());

        assertEquals("8f14e45f-ceea-4c1b-9d3b-1a2b3c4d5e6f", user.subject());
        assertEquals(1L, user.accountId());
        assertEquals(List.of("CUSTOMER"), user.roles());
        assertEquals("auth-stub", user.issuer());
    }

    @Test
    @DisplayName("a token signed with another key is refused, which is the point of verifying")
    void testVerify_WrongSignature() {
        Instant now = Instant.now();
        String forged = token(OTHER_KEY, Map.of("accountId", 1, "roles", List.of("CUSTOMER")),
                now, now.plus(Duration.ofMinutes(15)));

        assertThrows(InvalidTokenException.class, () -> verifier().verify(forged));
    }

    @Test
    void testVerify_Expired() {
        Instant longAgo = Instant.now().minus(Duration.ofHours(2));
        String expired = token(KEY, Map.of("accountId", 1, "roles", List.of("CUSTOMER")),
                longAgo, longAgo.plus(Duration.ofMinutes(15)));

        InvalidTokenException thrown =
                assertThrows(InvalidTokenException.class, () -> verifier().verify(expired));
        assertEquals("token expired", thrown.reason());
    }

    @Test
    @DisplayName("an unsigned token is not a token")
    void testVerify_Unsigned() {
        String unsigned = Jwts.builder()
                .subject("8f14e45f-ceea-4c1b-9d3b-1a2b3c4d5e6f")
                .claim("accountId", 1)
                .claim("roles", List.of("CUSTOMER"))
                .compact();

        assertThrows(InvalidTokenException.class, () -> verifier().verify(unsigned));
    }

    @Test
    void testVerify_Garbage() {
        assertThrows(InvalidTokenException.class, () -> verifier().verify("not-a-token"));
    }

    @Test
    void testVerify_EmptyString() {
        assertThrows(InvalidTokenException.class, () -> verifier().verify(""));
    }

    @Test
    void testVerify_MissingAccountIdClaim() {
        Instant now = Instant.now();
        String token = token(KEY, Map.of("roles", List.of("CUSTOMER")),
                now, now.plus(Duration.ofMinutes(15)));

        InvalidTokenException thrown =
                assertThrows(InvalidTokenException.class, () -> verifier().verify(token));
        assertEquals("accountId claim missing or not numeric", thrown.reason());
    }

    @Test
    @DisplayName("the roles claim is always present and never empty")
    void testVerify_EmptyRolesClaim() {
        Instant now = Instant.now();
        String token = token(KEY, Map.of("accountId", 1, "roles", List.of()),
                now, now.plus(Duration.ofMinutes(15)));

        assertThrows(InvalidTokenException.class, () -> verifier().verify(token));
    }

    @Test
    @DisplayName("the issuer is accepted by default, so the Sprint 8 cutover needs no code change")
    void testVerify_AnyIssuerByDefault() {
        assertEquals("auth-stub", verifier().verify(validToken()).issuer());
    }

    @Test
    @DisplayName("an issuer can be pinned once the cutover is done")
    void testVerify_RequiredIssuerEnforced() {
        assertThrows(InvalidTokenException.class,
                () -> verifierRequiringIssuer("auth-service").verify(validToken()));

        assertEquals("auth-stub", verifierRequiringIssuer("auth-stub").verify(validToken()).issuer());
    }

    @Test
    @DisplayName("the failure message is identical whatever went wrong")
    void testVerify_FailureMessageIsAlwaysTheSame() {
        InvalidTokenException expired = assertThrows(InvalidTokenException.class,
                () -> verifier().verify(token(KEY, Map.of("accountId", 1, "roles", List.of("CUSTOMER")),
                        Instant.now().minus(Duration.ofHours(2)),
                        Instant.now().minus(Duration.ofHours(1)))));
        InvalidTokenException garbage =
                assertThrows(InvalidTokenException.class, () -> verifier().verify("rubbish"));

        assertEquals(expired.getMessage(), garbage.getMessage());
        assertEquals("Unauthorised", expired.getMessage());
    }
}

package com.tradingplatform.portfolio.security;

import com.tradingplatform.portfolio.exception.UnauthorisedException;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import java.nio.charset.StandardCharsets;
import java.security.Key;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Verifies the access token issued by the auth service (or, in Sprints 6 and 7, the
 * Node auth stub) and extracts the claims this service needs.
 *
 * <p>This service verifies the signature itself, on every request. It does not trust
 * an upstream to have already checked it, per the security note on {@code bearerAuth}
 * in docs/contracts/portfolio-api.yaml: "Do not trust an upstream to have checked it."
 *
 * <p>Algorithm is HS256 with a shared secret from {@code JWT_SECRET}, matching the
 * signing rule in docs/contracts/auth-api.yaml. The {@code iss} claim is read but
 * never required to equal a specific value, because both {@code auth-stub} and
 * {@code auth-service} sign valid tokens.
 */
@Component
public class JwtService {

    private final Key signingKey;

    public JwtService(@Value("${jwt.secret}") String secret) {
        // HS256 needs at least 256 bits of key material. A short development secret
        // is padded deterministically rather than rejected, so that a team's first
        // "it works locally" run is not blocked by a key-length exception. Production
        // secrets must be long enough on their own; this padding is a development
        // convenience, not a substitute for a properly generated secret.
        byte[] keyBytes = secret.getBytes(StandardCharsets.UTF_8);
        if (keyBytes.length < 32) {
            byte[] padded = new byte[32];
            for (int i = 0; i < 32; i++) {
                padded[i] = keyBytes[i % keyBytes.length];
            }
            keyBytes = padded;
        }
        this.signingKey = Keys.hmacShaKeyFor(keyBytes);
    }

    /**
     * Verifies the token's signature and expiry, and returns the claims this service
     * relies on. Throws {@link UnauthorisedException} (AUTH-401) for anything wrong
     * with the token: missing, malformed, expired, or wrongly signed.
     */
    public AuthenticatedPrincipal verify(String bearerToken) {
        if (bearerToken == null || bearerToken.isBlank()) {
            throw new UnauthorisedException();
        }
        String token = bearerToken.startsWith("Bearer ") ? bearerToken.substring(7) : bearerToken;
        try {
            Claims claims = Jwts.parser()
                    .verifyWith((javax.crypto.SecretKey) signingKey)
                    .build()
                    .parseSignedClaims(token)
                    .getPayload();

            String subject = claims.getSubject();
            Number accountIdClaim = claims.get("accountId", Number.class);
            @SuppressWarnings("unchecked")
            List<String> roles = claims.get("roles", List.class);

            if (subject == null || accountIdClaim == null || roles == null || roles.isEmpty()) {
                throw new UnauthorisedException();
            }
            return new AuthenticatedPrincipal(subject, accountIdClaim.longValue(), roles);
        } catch (JwtException | IllegalArgumentException e) {
            throw new UnauthorisedException();
        }
    }
}

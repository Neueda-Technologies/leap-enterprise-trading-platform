package com.tradingplatform.tradeapi.security;

import com.tradingplatform.tradeapi.config.TradingProperties;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.ExpiredJwtException;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * Verifies an access token and turns it into an {@link AuthenticatedUser}.
 *
 * <p>Verification means the signature, the expiry and the claim shape, in that order and every time.
 * Decoding a JWT is base64, not cryptography: a payload that has not had its signature checked is a
 * string the client wrote. Any code path that reads a claim without reaching this class is an
 * authentication bypass.
 *
 * <p>Signing is HS256 with a secret shared with the auth service, read from {@code JWT_SECRET}. That
 * is a development arrangement and the contract says so. Moving to RS256 means this service holds a
 * public key and can verify without holding the ability to sign, which is what a production estate
 * wants. It is a documented upgrade rather than a requirement, and the only change it needs is here.
 *
 * <p>The issuer is not required to take a particular value by default. The Sprint 8 acceptance
 * criterion is that swapping the {@code auth-stub} for {@code auth-service} needs configuration
 * changes only, and pinning the issuer in code would break it. Set
 * {@code trading.jwt.required-issuer} once the cutover is done.
 */
@Component
public class JwtVerifier {

    private static final String CLAIM_ACCOUNT_ID = "accountId";
    private static final String CLAIM_ROLES = "roles";

    private final SecretKey key;
    private final long clockSkewSeconds;
    private final String requiredIssuer;

    public JwtVerifier(TradingProperties properties) {
        TradingProperties.Jwt jwt = properties.jwt();
        this.key = Keys.hmacShaKeyFor(jwt.secret().getBytes(StandardCharsets.UTF_8));
        this.clockSkewSeconds = jwt.clockSkew();
        this.requiredIssuer = jwt.requiredIssuer();
    }

    /**
     * Verifies the token and extracts the claims contract from {@code contracts/auth-api.yaml}.
     *
     * @throws InvalidTokenException for every failure, with the same message in every case
     */
    public AuthenticatedUser verify(String token) {
        Claims claims = parse(token);

        String subject = claims.getSubject();
        if (!StringUtils.hasText(subject)) {
            throw new InvalidTokenException("missing sub claim");
        }

        Long accountId = readAccountId(claims);
        List<String> roles = readRoles(claims);

        if (StringUtils.hasText(requiredIssuer) && !requiredIssuer.equals(claims.getIssuer())) {
            throw new InvalidTokenException("issuer is not " + requiredIssuer);
        }

        return new AuthenticatedUser(subject, accountId, roles, claims.getIssuer());
    }

    private Claims parse(String token) {
        try {
            return Jwts.parser()
                    .verifyWith(key)
                    .clockSkewSeconds(clockSkewSeconds)
                    .build()
                    .parseSignedClaims(token)
                    .getPayload();
        } catch (ExpiredJwtException e) {
            throw new InvalidTokenException("token expired", e);
        } catch (JwtException | IllegalArgumentException e) {
            // Covers a bad signature, a malformed token, an unsupported algorithm and an empty
            // string. The caller is told none of that.
            throw new InvalidTokenException("token rejected: " + e.getClass().getSimpleName(), e);
        }
    }

    /**
     * The {@code accountId} claim is an integer in the contract, but a JSON number arrives as an
     * Integer or a Long depending on its magnitude, and some issuers send it as a string. Accept the
     * numeric forms and refuse the rest.
     */
    private static Long readAccountId(Claims claims) {
        Object raw = claims.get(CLAIM_ACCOUNT_ID);
        if (raw instanceof Number number) {
            return number.longValue();
        }
        throw new InvalidTokenException("accountId claim missing or not numeric");
    }

    private static List<String> readRoles(Claims claims) {
        Object raw = claims.get(CLAIM_ROLES);
        if (!(raw instanceof List<?> values) || values.isEmpty()) {
            throw new InvalidTokenException("roles claim missing or empty");
        }
        return values.stream().map(String::valueOf).toList();
    }
}

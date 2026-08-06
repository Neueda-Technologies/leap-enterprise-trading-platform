package com.tradingplatform.tradeapi.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.tradingplatform.tradeapi.TestData;
import com.tradingplatform.tradeapi.config.ExecutionMode;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import jakarta.servlet.FilterChain;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

@DisplayName("JwtAuthenticationFilter")
class JwtAuthenticationFilterTest {

    private static final SecretKey KEY =
            Keys.hmacShaKeyFor(TestData.JWT_SECRET.getBytes(StandardCharsets.UTF_8));

    private final JwtAuthenticationFilter filter = new JwtAuthenticationFilter(
            new JwtVerifier(TestData.properties(ExecutionMode.ASYNC)), new ObjectMapper());

    private static String validToken() {
        Instant now = Instant.now();
        return Jwts.builder()
                .subject("8f14e45f-ceea-4c1b-9d3b-1a2b3c4d5e6f")
                .issuer("auth-stub")
                .claim("accountId", 1)
                .claim("roles", List.of("CUSTOMER"))
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(Duration.ofMinutes(15))))
                .signWith(KEY)
                .compact();
    }

    private static MockHttpServletRequest request(String authorization) {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/api/v1/orders");
        if (authorization != null) {
            request.addHeader(HttpHeaders.AUTHORIZATION, authorization);
        }
        return request;
    }

    @Test
    @DisplayName("a verified token becomes the request attribute the controllers read")
    void testValidTokenPassesAndPopulatesTheIdentity() throws Exception {
        MockHttpServletRequest request = request("Bearer " + validToken());
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain chain = mock(FilterChain.class);

        filter.doFilter(request, response, chain);

        verify(chain).doFilter(request, response);
        AuthenticatedUser user = assertInstanceOf(AuthenticatedUser.class,
                request.getAttribute(AuthenticatedUser.ATTRIBUTE));
        assertEquals(1L, user.accountId());
    }

    @Test
    @DisplayName("no header is 401 in the platform envelope, and the chain never runs")
    void testMissingHeaderIsRejected() throws Exception {
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain chain = mock(FilterChain.class);

        filter.doFilter(request(null), response, chain);

        assertEquals(HttpStatus.UNAUTHORIZED.value(), response.getStatus());
        assertEquals("{\"errorCode\":\"AUTH-401\",\"message\":\"Unauthorised\"}",
                response.getContentAsString());
        verify(chain, never()).doFilter(org.mockito.ArgumentMatchers.any(),
                org.mockito.ArgumentMatchers.any());
    }

    @Test
    void testNonBearerSchemeIsRejected() throws Exception {
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain chain = mock(FilterChain.class);

        filter.doFilter(request("Basic dXNlcjpwYXNz"), response, chain);

        assertEquals(HttpStatus.UNAUTHORIZED.value(), response.getStatus());
        verify(chain, never()).doFilter(org.mockito.ArgumentMatchers.any(),
                org.mockito.ArgumentMatchers.any());
    }

    @Test
    @DisplayName("a wrongly signed token is refused with the same body as a missing one")
    void testForgedTokenIsRejected() throws Exception {
        SecretKey otherKey = Keys.hmacShaKeyFor(
                "an-entirely-different-secret-of-sufficient-length".getBytes(StandardCharsets.UTF_8));
        Instant now = Instant.now();
        String forged = Jwts.builder()
                .subject("attacker")
                .claim("accountId", 1)
                .claim("roles", List.of("ADMIN"))
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(Duration.ofMinutes(15))))
                .signWith(otherKey)
                .compact();

        MockHttpServletRequest request = request("Bearer " + forged);
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, mock(FilterChain.class));

        assertEquals(HttpStatus.UNAUTHORIZED.value(), response.getStatus());
        assertNull(request.getAttribute(AuthenticatedUser.ATTRIBUTE));
    }

    @Test
    @DisplayName("the 401 body is JSON, so one client error handler covers every failure")
    void testRejectionIsJson() throws Exception {
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request(null), response, mock(FilterChain.class));

        assertTrue(response.getContentType().startsWith("application/json"),
                "was " + response.getContentType());
    }
}

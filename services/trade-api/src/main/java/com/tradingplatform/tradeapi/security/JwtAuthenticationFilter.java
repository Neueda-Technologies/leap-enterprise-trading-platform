package com.tradingplatform.tradeapi.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.tradingplatform.tradeapi.web.dto.ErrorResponse;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * Rejects any request to {@code /api/**} that does not carry a verified token.
 *
 * <p>A filter rather than a check inside each controller, for one reason: a check you have to
 * remember to write is a check somebody eventually forgets to write, and the endpoint they forget it
 * on is unauthenticated with no compile error and no failing test to say so. The filter is mapped by
 * URL pattern in {@link com.tradingplatform.tradeapi.config.SecurityFilterConfig}, so a route added
 * next sprint is protected before anyone writes its controller.
 *
 * <p>The filter answers one question: is this caller who they say they are. It does not decide what
 * they may reach. That is authorisation, it needs the account the request is addressing, and it lives
 * in the service layer where the account is known. Conflating the two produces a filter that has to
 * parse request bodies.
 *
 * <p>Failures are written here rather than thrown, because a filter runs outside the dispatcher and
 * an exception thrown from it never reaches {@code @ControllerAdvice}. The body is the same
 * {@code ErrorResponse} envelope the rest of the API uses, so the Angular UI has one error handler.
 */
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(JwtAuthenticationFilter.class);
    private static final String BEARER_PREFIX = "Bearer ";

    private final JwtVerifier verifier;
    private final ObjectMapper objectMapper;

    public JwtAuthenticationFilter(JwtVerifier verifier, ObjectMapper objectMapper) {
        this.verifier = verifier;
        this.objectMapper = objectMapper;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String header = request.getHeader(HttpHeaders.AUTHORIZATION);
        if (header == null || !header.startsWith(BEARER_PREFIX)) {
            reject(request, response, "no bearer token");
            return;
        }

        AuthenticatedUser user;
        try {
            user = verifier.verify(header.substring(BEARER_PREFIX.length()).trim());
        } catch (InvalidTokenException e) {
            reject(request, response, e.reason());
            return;
        }

        request.setAttribute(AuthenticatedUser.ATTRIBUTE, user);
        chain.doFilter(request, response);
    }

    private void reject(HttpServletRequest request, HttpServletResponse response, String reason)
            throws IOException {
        // The reason goes to the log and never to the caller. The token itself is never logged: it
        // is a bearer credential, and a log aggregator is not a place to store one.
        log.warn("Rejected unauthenticated request method={} path={} reason={}",
                request.getMethod(), request.getRequestURI(), reason);

        response.setStatus(HttpStatus.UNAUTHORIZED.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding("UTF-8");
        objectMapper.writeValue(response.getOutputStream(), ErrorResponse.unauthorised());
    }
}

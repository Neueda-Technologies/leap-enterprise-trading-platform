package com.tradingplatform.portfolio.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.tradingplatform.portfolio.exception.UnauthorisedException;
import com.tradingplatform.portfolio.web.dto.ErrorResponse;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Verifies the bearer token on every {@code /api/**} route and populates
 * {@link PrincipalContext} for the controller layer. {@code /health} is excluded, per
 * the {@code security: []} override on that operation in portfolio-api.yaml.
 *
 * <p>This service does the same verification the Trade REST API does: check the
 * signature and expiry itself, on every request, rather than trusting a gateway or an
 * upstream service to have already done it.
 */
@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private static final String AUTHORIZATION_HEADER = "Authorization";

    private final JwtService jwtService;
    private final ObjectMapper objectMapper;

    public JwtAuthenticationFilter(JwtService jwtService, ObjectMapper objectMapper) {
        this.jwtService = jwtService;
        this.objectMapper = objectMapper;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !request.getRequestURI().startsWith("/api/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        try {
            String header = request.getHeader(AUTHORIZATION_HEADER);
            AuthenticatedPrincipal principal = jwtService.verify(header);
            PrincipalContext.set(principal);
            chain.doFilter(request, response);
        } catch (UnauthorisedException e) {
            writeError(response, e.getStatus().value(), e.getErrorCode(), e.getMessage());
        } finally {
            PrincipalContext.clear();
        }
    }

    private void writeError(HttpServletResponse response, int status, String errorCode, String message)
            throws IOException {
        response.setStatus(status);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        objectMapper.writeValue(response.getWriter(), new ErrorResponse(errorCode, message));
    }
}

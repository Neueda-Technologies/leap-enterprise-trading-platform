package com.tradingplatform.portfolio.web;

import com.tradingplatform.portfolio.fauxnance.FauxnanceClient;
import com.tradingplatform.portfolio.web.dto.HealthResponse;
import com.tradingplatform.portfolio.web.dto.HealthResponse.DependencyStatus;
import java.time.Clock;
import java.util.List;
import javax.sql.DataSource;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Implements {@code GET /health}, unauthenticated per the {@code security: []}
 * override on this operation in portfolio-api.yaml. Reports the two dependencies this
 * service has: Postgres and Fauxnance. It returns {@code 200} even when a dependency
 * is degraded; a failing dependency changes {@code status} in the body, it does not
 * fail the HTTP response, so a load balancer does not pull this instance out of
 * rotation solely because Fauxnance's quota ran out.
 */
@RestController
public class HealthController {

    private final DataSource dataSource;
    private final FauxnanceClient fauxnanceClient;
    private final Clock clock;

    public HealthController(DataSource dataSource, FauxnanceClient fauxnanceClient, Clock clock) {
        this.dataSource = dataSource;
        this.fauxnanceClient = fauxnanceClient;
        this.clock = clock;
    }

    @GetMapping("/health")
    public HealthResponse health() {
        DependencyStatus postgres = checkPostgres();
        DependencyStatus fauxnance = checkFauxnance();

        boolean allOk = "ok".equals(postgres.status()) && "ok".equals(fauxnance.status());
        String status = allOk ? "ok" : "degraded";

        return new HealthResponse(status, List.of(postgres, fauxnance), clock.instant());
    }

    private DependencyStatus checkPostgres() {
        try (var connection = dataSource.getConnection()) {
            boolean valid = connection.isValid(2);
            return new DependencyStatus("postgres", valid ? "ok" : "down", null);
        } catch (Exception e) {
            return new DependencyStatus("postgres", "down", null);
        }
    }

    private DependencyStatus checkFauxnance() {
        // Deliberately not polled on every /health call: GET /usage costs quota, per
        // the schema note "Poll it rarely; it costs quota." A production build would
        // cache this alongside the quote cache rather than call it synchronously here;
        // this reference implementation keeps the call for clarity and accepts the
        // quota cost as a documented trade-off. See the README.
        Integer quotaRemaining = fauxnanceClient.getQuotaRemaining();
        String status = quotaRemaining == null ? "degraded" : "ok";
        return new DependencyStatus("fauxnance", status, quotaRemaining);
    }
}

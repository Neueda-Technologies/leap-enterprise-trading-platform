package com.tradingplatform.portfolio.web.dto;

import java.time.Instant;
import java.util.List;

/** Matches {@code HealthResponse} in docs/contracts/portfolio-api.yaml. */
public record HealthResponse(String status, List<DependencyStatus> dependencies, Instant asOf) {

    public record DependencyStatus(String name, String status, Integer quotaRemaining) {
    }
}

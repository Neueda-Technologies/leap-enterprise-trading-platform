package com.tradingplatform.portfolio.exception;

import org.springframework.http.HttpStatus;

/**
 * MKT-503: no price could be obtained for any held instrument, because Fauxnance is
 * unreachable or the daily quota is exhausted. This code extends the platform error
 * catalogue and is scoped to services that price against a market feed, per
 * docs/contracts/portfolio-api.yaml.
 */
public class PricingUnavailableException extends ApiException {

    public PricingUnavailableException() {
        super("MKT-503", HttpStatus.SERVICE_UNAVAILABLE, "Pricing unavailable");
    }
}

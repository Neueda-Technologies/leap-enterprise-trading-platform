package com.tradingplatform.portfolio.fauxnance;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

@Component
public class FauxnanceHttpClient implements FauxnanceClient {

    private static final Logger log = LoggerFactory.getLogger(FauxnanceHttpClient.class);

    private final RestClient restClient;
    private final FauxnanceProperties properties;

    public FauxnanceHttpClient(RestClient fauxnanceRestClient, FauxnanceProperties properties) {
        this.restClient = fauxnanceRestClient;
        this.properties = properties;
    }

    @Override
    public Map<String, Quote> getQuotes(List<String> symbols) {
        Map<String, Quote> result = new LinkedHashMap<>();
        int batchSize = Math.max(1, properties.quoteBatchSize());
        for (int start = 0; start < symbols.size(); start += batchSize) {
            List<String> batch = symbols.subList(start, Math.min(start + batchSize, symbols.size()));
            result.putAll(fetchBatch(batch));
        }
        return result;
    }

    private Map<String, Quote> fetchBatch(List<String> batch) {
        String symbolParam = String.join(",", batch);
        try {
            FauxnanceQuoteDto[] response = restClient
                    .get()
                    .uri(uriBuilder -> uriBuilder
                            .path("/quotes")
                            .queryParam("symbols", symbolParam)
                            .build())
                    .retrieve()
                    .body(FauxnanceQuoteDto[].class);

            Map<String, Quote> quotes = new LinkedHashMap<>();
            if (response != null) {
                for (FauxnanceQuoteDto dto : response) {
                    if (dto.symbol() == null || dto.price() == null) {
                        continue;
                    }
                    quotes.put(dto.symbol(), new Quote(dto.symbol(), dto.price(), dto.currency(), dto.quoteAsOf(), dto.stale()));
                }
            }
            return quotes;
        } catch (RestClientException e) {
            log.warn("Fauxnance batch quote call failed for symbols [{}]: {}", symbolParam, e.getMessage());
            return Map.of();
        }
    }

    @Override
    public Integer getQuotaRemaining() {
        try {
            UsageDto usage = restClient.get().uri("/usage").retrieve().body(UsageDto.class);
            return usage == null ? null : usage.quotaRemaining();
        } catch (RestClientException e) {
            log.warn("Fauxnance usage call failed: {}", e.getMessage());
            return null;
        }
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private record UsageDto(Integer quotaRemaining) {
    }
}

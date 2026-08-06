package com.tradingplatform.portfolio.web.dto;

/** The standard error envelope, shared with the Trade REST API and the auth service. */
public record ErrorResponse(String errorCode, String message) {
}

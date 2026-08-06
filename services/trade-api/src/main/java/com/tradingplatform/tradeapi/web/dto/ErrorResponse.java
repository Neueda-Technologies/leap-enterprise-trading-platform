package com.tradingplatform.tradeapi.web.dto;

import com.tradingplatform.tradeapi.security.InvalidTokenException;
import io.swagger.v3.oas.annotations.media.Schema;

/**
 * The single error envelope for every failure in the platform.
 *
 * <p>Two fields and no more. Clients branch on {@code errorCode}, never on {@code message} and never
 * on the HTTP status alone, because 404 and 409 each carry two codes in this catalogue.
 *
 * <p>{@code message} is short, human-readable and deliberately unhelpful to an attacker. No stack
 * trace, no SQL fragment, no class name, no internal identifier. Everything an engineer needs to
 * diagnose the failure is on the server, in the log line the handler wrote, correlated by the
 * request path and time.
 *
 * @param errorCode one of {@code ACC-404}, {@code ACC-403}, {@code INS-404}, {@code ORD-400},
 *                  {@code ORD-409}, {@code VAL-422}, {@code AUTH-401}
 * @param message   short description for a human
 */
@Schema(name = "ErrorResponse", description = "The single error envelope for every failure.")
public record ErrorResponse(

        @Schema(example = "ORD-409") String errorCode,

        @Schema(example = "Insufficient holdings") String message) {

    /** The 401 body. Identical for a missing, malformed, expired or wrongly signed token. */
    public static ErrorResponse unauthorised() {
        return new ErrorResponse(InvalidTokenException.ERROR_CODE, "Unauthorised");
    }
}

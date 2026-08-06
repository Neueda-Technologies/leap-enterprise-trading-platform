package com.tradingplatform.tradeapi.web.dto;

import com.tradingplatform.domain.model.Position;
import io.swagger.v3.oas.annotations.media.Schema;

import java.math.BigDecimal;

/**
 * One holding.
 *
 * <p>Market value is not here, for the same reason it is not on the balance: it needs a live quote.
 *
 * <p>{@code averageCost} is the weighted average cost basis per unit. A buy recalculates it. A sell
 * reduces the quantity and leaves it unchanged, which is what makes realised profit and loss
 * computable later.
 *
 * @param accountId   the numeric account key
 * @param symbol      the instrument
 * @param quantity    net held quantity, never negative
 * @param averageCost weighted average cost basis per unit
 */
@Schema(name = "PositionResponse")
public record PositionResponse(

        @Schema(example = "1") Long accountId,

        @Schema(example = "ACME") String symbol,

        @Schema(description = "Net held quantity. Never negative; short selling is out of scope.",
                example = "100")
        int quantity,

        @Schema(example = "25.50") BigDecimal averageCost) {

    public static PositionResponse of(Position position) {
        return new PositionResponse(
                position.getAccountId(),
                position.getSymbol(),
                position.getQuantity(),
                position.getAverageCost());
    }
}

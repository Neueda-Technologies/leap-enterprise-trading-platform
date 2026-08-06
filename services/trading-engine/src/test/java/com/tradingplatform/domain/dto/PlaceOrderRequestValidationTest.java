package com.tradingplatform.domain.dto;

import com.tradingplatform.domain.model.OrderSide;
import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.Set;
import java.util.stream.Collectors;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Bean Validation on the order request.
 *
 * <p>Named in the Sprint 5 acceptance criteria. It must be green.
 *
 * <p>These constraints are the syntactic gate. They reject a malformed body before it reaches the
 * service and before it reaches the database, and the Trade REST API returns {@code VAL-422} when
 * one fires. They do not replace business rules 4 and 5:
 * {@link com.tradingplatform.domain.service.OrderPlacementService} re-checks both, because the
 * domain has to hold for a caller that never ran a validator.
 */
@DisplayName("PlaceOrderRequest validation")
class PlaceOrderRequestValidationTest {

    private static ValidatorFactory factory;
    private static Validator validator;

    @BeforeAll
    static void openValidator() {
        factory = Validation.buildDefaultValidatorFactory();
        validator = factory.getValidator();
    }

    @AfterAll
    static void closeValidator() {
        factory.close();
    }

    private static PlaceOrderRequest valid() {
        return new PlaceOrderRequest(1L, "ACME", OrderSide.BUY, 100,
                new BigDecimal("25.50"), "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e");
    }

    private Set<String> violatedFields(PlaceOrderRequest request) {
        return validator.validate(request).stream()
                .map(ConstraintViolation::getPropertyPath)
                .map(Object::toString)
                .collect(Collectors.toSet());
    }

    @Test
    void testValidRequestPasses() {
        assertTrue(validator.validate(valid()).isEmpty());
    }

    @Test
    void testAccountIdIsRequired() {
        PlaceOrderRequest request = new PlaceOrderRequest(null, "ACME", OrderSide.BUY, 100,
                new BigDecimal("25.50"), "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e");

        assertTrue(violatedFields(request).contains("accountId"));
    }

    @Test
    @DisplayName("accountId is the numeric key, so zero and negative values are not identifiers")
    void testAccountIdMustBePositive() {
        PlaceOrderRequest request = new PlaceOrderRequest(0L, "ACME", OrderSide.BUY, 100,
                new BigDecimal("25.50"), "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e");

        assertTrue(violatedFields(request).contains("accountId"));
    }

    @Test
    void testSymbolIsRequired() {
        PlaceOrderRequest request = new PlaceOrderRequest(1L, "  ", OrderSide.BUY, 100,
                new BigDecimal("25.50"), "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e");

        assertTrue(violatedFields(request).contains("symbol"));
    }

    @Test
    void testSymbolIsBoundedToTwentyCharacters() {
        PlaceOrderRequest request = new PlaceOrderRequest(1L, "A".repeat(21), OrderSide.BUY, 100,
                new BigDecimal("25.50"), "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e");

        assertTrue(violatedFields(request).contains("symbol"));
    }

    @Test
    @DisplayName("the Fauxnance symbol scheme passes: suffixes, prefixes and plain tickers")
    void testVenuePrefixedSymbolsPass() {
        for (String symbol : new String[] {"AAPL", "INFY.NS", "RELIANCE.NS", "FX:EURUSD", "X:BTC-USD"}) {
            PlaceOrderRequest request = new PlaceOrderRequest(1L, symbol, OrderSide.BUY, 100,
                    new BigDecimal("25.50"), "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e");

            assertTrue(validator.validate(request).isEmpty(), symbol + " should be accepted");
        }
    }

    @Test
    void testSideIsRequired() {
        PlaceOrderRequest request = new PlaceOrderRequest(1L, "ACME", null, 100,
                new BigDecimal("25.50"), "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e");

        assertTrue(violatedFields(request).contains("side"));
    }

    @Test
    @DisplayName("business rule 4 at the gate: quantity zero is refused")
    void testQuantityMustBeGreaterThanZero() {
        PlaceOrderRequest request = new PlaceOrderRequest(1L, "ACME", OrderSide.BUY, 0,
                new BigDecimal("25.50"), "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e");

        assertTrue(violatedFields(request).contains("quantity"));
    }

    @Test
    void testNegativeQuantityIsRefused() {
        PlaceOrderRequest request = new PlaceOrderRequest(1L, "ACME", OrderSide.BUY, -1,
                new BigDecimal("25.50"), "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e");

        assertTrue(violatedFields(request).contains("quantity"));
    }

    @Test
    @DisplayName("business rule 5 at the gate: price zero is refused")
    void testPriceMustBeGreaterThanZero() {
        PlaceOrderRequest request = new PlaceOrderRequest(1L, "ACME", OrderSide.BUY, 100,
                new BigDecimal("0.00"), "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e");

        assertTrue(violatedFields(request).contains("price"));
    }

    @Test
    void testNegativePriceIsRefused() {
        PlaceOrderRequest request = new PlaceOrderRequest(1L, "ACME", OrderSide.BUY, 100,
                new BigDecimal("-0.01"), "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e");

        assertTrue(violatedFields(request).contains("price"));
    }

    @Test
    @DisplayName("prices are quoted to two decimal places, so a third is refused")
    void testPriceIsLimitedToTwoDecimalPlaces() {
        PlaceOrderRequest request = new PlaceOrderRequest(1L, "ACME", OrderSide.BUY, 100,
                new BigDecimal("25.505"), "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e");

        assertTrue(violatedFields(request).contains("price"));
    }

    @Test
    void testIdempotencyKeyIsRequired() {
        PlaceOrderRequest request = new PlaceOrderRequest(1L, "ACME", OrderSide.BUY, 100,
                new BigDecimal("25.50"), "");

        assertTrue(violatedFields(request).contains("idempotencyKey"));
    }

    @Test
    @DisplayName("a short key is refused, because a short key collides")
    void testIdempotencyKeyHasAMinimumLength() {
        PlaceOrderRequest request = new PlaceOrderRequest(1L, "ACME", OrderSide.BUY, 100,
                new BigDecimal("25.50"), "abc");

        assertTrue(violatedFields(request).contains("idempotencyKey"));
    }

    @Test
    void testIdempotencyKeyIsBoundedToOneHundredCharacters() {
        PlaceOrderRequest request = new PlaceOrderRequest(1L, "ACME", OrderSide.BUY, 100,
                new BigDecimal("25.50"), "k".repeat(101));

        assertTrue(violatedFields(request).contains("idempotencyKey"));
    }

    @Test
    @DisplayName("every field is reported at once, so the caller fixes the body in one attempt")
    void testAllViolationsAreReportedTogether() {
        PlaceOrderRequest request = new PlaceOrderRequest(null, "", OrderSide.BUY, 0,
                new BigDecimal("0.00"), "");

        assertEquals(Set.of("accountId", "symbol", "quantity", "price", "idempotencyKey"),
                violatedFields(request));
    }
}

package com.tradingplatform.tradeapi;

import com.tradingplatform.domain.dto.PlaceOrderRequest;
import com.tradingplatform.domain.model.Account;
import com.tradingplatform.domain.model.AccountStatus;
import com.tradingplatform.domain.model.Instrument;
import com.tradingplatform.domain.model.Money;
import com.tradingplatform.domain.model.Order;
import com.tradingplatform.domain.model.OrderSide;
import com.tradingplatform.domain.model.OrderStatus;
import com.tradingplatform.domain.model.Position;
import com.tradingplatform.tradeapi.config.ExecutionMode;
import com.tradingplatform.tradeapi.config.TradingProperties;
import com.tradingplatform.tradeapi.security.AuthenticatedUser;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/** Fixtures shared by the service, controller and security tests. */
public final class TestData {

    public static final Long ACCOUNT_ID = 1L;
    public static final String SYMBOL = "ACME";
    public static final Instant NOW = Instant.parse("2026-09-28T09:14:22Z");
    public static final UUID ORDER_ID = UUID.fromString("6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e");
    public static final String IDEMPOTENCY_KEY = "6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e";

    /** At least 32 characters, which HS256 requires. */
    public static final String JWT_SECRET = "test-secret-that-is-long-enough-for-hs256";

    private TestData() {
    }

    public static AuthenticatedUser customer() {
        return new AuthenticatedUser("8f14e45f-ceea-4c1b-9d3b-1a2b3c4d5e6f", ACCOUNT_ID,
                List.of("CUSTOMER"), "auth-stub");
    }

    public static AuthenticatedUser customerOf(Long accountId) {
        return new AuthenticatedUser("8f14e45f-ceea-4c1b-9d3b-1a2b3c4d5e6f", accountId,
                List.of("CUSTOMER"), "auth-stub");
    }

    public static Account account(String cash) {
        return account(cash, AccountStatus.ACTIVE, 0);
    }

    public static Account account(String cash, AccountStatus status, int version) {
        return new Account(ACCOUNT_ID, "ACC-000001", "Priya Menon",
                Money.of(cash), status, version, NOW);
    }

    public static Instrument instrument() {
        return new Instrument(SYMBOL, "Acme Corporation", "EQUITY", "USD", true);
    }

    public static Position position(int quantity, String averageCost) {
        return new Position(ACCOUNT_ID, SYMBOL, quantity, Money.of(averageCost));
    }

    public static PlaceOrderRequest request(OrderSide side, int quantity, String price) {
        return new PlaceOrderRequest(ACCOUNT_ID, SYMBOL, side, quantity,
                Money.of(price), IDEMPOTENCY_KEY);
    }

    public static Order order(OrderStatus status) {
        return new Order(ORDER_ID, ACCOUNT_ID, SYMBOL, OrderSide.BUY, 100, Money.of("25.50"),
                status, IDEMPOTENCY_KEY, NOW, null, null, null);
    }

    public static BigDecimal money(String value) {
        return Money.of(value);
    }

    public static TradingProperties properties(ExecutionMode mode) {
        return new TradingProperties(
                mode,
                "USD",
                new TradingProperties.Jwt(JWT_SECRET, 30, ""),
                new TradingProperties.Kafka(true, "orders", "trade-events"));
    }
}

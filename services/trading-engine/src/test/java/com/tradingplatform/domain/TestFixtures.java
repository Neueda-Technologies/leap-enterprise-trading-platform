package com.tradingplatform.domain;

import com.tradingplatform.domain.dto.PlaceOrderRequest;
import com.tradingplatform.domain.model.Account;
import com.tradingplatform.domain.model.AccountStatus;
import com.tradingplatform.domain.model.Instrument;
import com.tradingplatform.domain.model.Money;
import com.tradingplatform.domain.model.Order;
import com.tradingplatform.domain.model.OrderSide;
import com.tradingplatform.domain.model.Position;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

/**
 * Fixtures shared by the domain tests.
 *
 * <p>Every fixture is a plain object. There is no framework here and there is nothing to start,
 * which is the whole point of keeping the rules in a library: the suite runs in under a second and
 * a failure points at a rule rather than at a container.
 */
public final class TestFixtures {

    public static final Long ACCOUNT_ID = 1L;
    public static final String SYMBOL = "ACME";
    public static final Instant NOW = Instant.parse("2026-09-28T09:14:22Z");

    private TestFixtures() {
    }

    /** An ACTIVE account holding the given cash. */
    public static Account account(String cash) {
        return account(cash, AccountStatus.ACTIVE);
    }

    public static Account account(String cash, AccountStatus status) {
        return new Account(ACCOUNT_ID, "ACC-000001", "Priya Menon", Money.of(cash), status, 0, NOW);
    }

    /** A tradable instrument. */
    public static Instrument instrument() {
        return new Instrument(SYMBOL, "Acme Corporation", "EQUITY", "USD", true);
    }

    /** An instrument that exists but is suspended from trading. */
    public static Instrument suspendedInstrument() {
        return new Instrument(SYMBOL, "Acme Corporation", "EQUITY", "USD", false);
    }

    public static Position position(int quantity, String averageCost) {
        return new Position(ACCOUNT_ID, SYMBOL, quantity, Money.of(averageCost));
    }

    public static PlaceOrderRequest request(OrderSide side, int quantity, String price) {
        return new PlaceOrderRequest(
                ACCOUNT_ID, SYMBOL, side, quantity, Money.of(price), UUID.randomUUID().toString());
    }

    public static PlaceOrderRequest request(OrderSide side, int quantity, String price, String key) {
        return new PlaceOrderRequest(ACCOUNT_ID, SYMBOL, side, quantity, Money.of(price), key);
    }

    /** A working order in status NEW. */
    public static Order order(OrderSide side, int quantity, String price) {
        return Order.accept(UUID.randomUUID(), ACCOUNT_ID, SYMBOL, side, quantity,
                Money.of(price), UUID.randomUUID().toString(), NOW);
    }

    /** Shorthand for a money literal at the platform scale. */
    public static BigDecimal money(String value) {
        return Money.of(value);
    }
}

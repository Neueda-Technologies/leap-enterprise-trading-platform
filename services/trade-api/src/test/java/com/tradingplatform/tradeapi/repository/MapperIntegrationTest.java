package com.tradingplatform.tradeapi.repository;

import com.tradingplatform.domain.model.Account;
import com.tradingplatform.domain.model.AccountStatus;
import com.tradingplatform.domain.model.Instrument;
import com.tradingplatform.domain.model.Money;
import com.tradingplatform.domain.model.Order;
import com.tradingplatform.domain.model.OrderSide;
import com.tradingplatform.domain.model.OrderStatus;
import com.tradingplatform.domain.model.Position;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mybatis.spring.boot.test.autoconfigure.MybatisTest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DuplicateKeyException;
import com.tradingplatform.tradeapi.config.MyBatisConfig;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.jdbc.Sql;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * The mapper SQL, against a real database engine.
 *
 * <p>H2 in PostgreSQL mode, so the suite runs in about a second and needs no Docker. That buys speed
 * and costs fidelity: H2 is not Postgres, and a statement that passes here can still fail there. The
 * compose stack is the acceptance environment. This is the loop you run while you are writing the
 * SQL.
 *
 * <p>The tests that matter most are the ones a mock cannot express: the unique constraint that is
 * business rule 8, the optimistic lock predicate, and the guarded status transitions. Each of those
 * is a claim about what the database does, and only a database can settle it.
 */
@MybatisTest
@Import(MyBatisConfig.class)
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:h2:mem:trading;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.datasource.username=sa",
        "spring.datasource.password="
})
@Sql(scripts = "/schema-h2.sql", executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD)
@DisplayName("Mappers")
class MapperIntegrationTest {

    private static final Long ACTIVE_ACCOUNT = 1L;
    private static final Long POOR_ACCOUNT = 2L;
    private static final Long SUSPENDED_ACCOUNT = 3L;
    private static final Instant NOW = Instant.parse("2026-09-28T09:14:22Z");

    @Autowired private AccountMapper accountMapper;
    @Autowired private InstrumentMapper instrumentMapper;
    @Autowired private OrderMapper orderMapper;
    @Autowired private PositionMapper positionMapper;

    private Order newOrder(String idempotencyKey) {
        return Order.accept(UUID.randomUUID(), ACTIVE_ACCOUNT, "ACME", OrderSide.BUY, 100,
                Money.of("25.50"), idempotencyKey, NOW);
    }

    @Nested
    @DisplayName("accounts")
    class Accounts {

        @Test
        @DisplayName("both identifiers, the status and the lock version come back typed")
        void testFindById() {
            Account account = accountMapper.findById(ACTIVE_ACCOUNT);

            assertNotNull(account);
            assertEquals(ACTIVE_ACCOUNT, account.getId());
            assertEquals("ACC-000001", account.getAccountId());
            assertEquals(AccountStatus.ACTIVE, account.getStatus());
            assertEquals(0, account.getCashBalance().compareTo(Money.of("24500.75")));
            assertEquals(0, account.getVersion());
            assertEquals(NOW, account.getLastUpdated());
        }

        @Test
        void testFindById_Unknown() {
            assertNull(accountMapper.findById(999L));
        }

        @Test
        void testFindById_SuspendedAccountIsStillReturned() {
            assertEquals(AccountStatus.SUSPENDED, accountMapper.findById(SUSPENDED_ACCOUNT).getStatus());
        }

        @Test
        @DisplayName("a write at the expected version succeeds and moves the version on")
        void testUpdateCashBalance() {
            int rows = accountMapper.updateCashBalance(
                    ACTIVE_ACCOUNT, Money.of("100.00"), 0, NOW);

            assertEquals(1, rows);
            Account after = accountMapper.findById(ACTIVE_ACCOUNT);
            assertEquals(0, after.getCashBalance().compareTo(Money.of("100.00")));
            assertEquals(1, after.getVersion());
        }

        @Test
        @DisplayName("a write at a stale version affects nothing, which is the whole mechanism")
        void testUpdateCashBalance_StaleVersion() {
            int rows = accountMapper.updateCashBalance(
                    ACTIVE_ACCOUNT, Money.of("100.00"), 7, NOW);

            assertEquals(0, rows);
            assertEquals(0, accountMapper.findById(ACTIVE_ACCOUNT)
                    .getCashBalance().compareTo(Money.of("24500.75")));
        }

        @Test
        @DisplayName("the second of two writes at the same version loses")
        void testUpdateCashBalance_SecondWriterLoses() {
            assertEquals(1, accountMapper.updateCashBalance(POOR_ACCOUNT, Money.of("10.00"), 3, NOW));
            assertEquals(0, accountMapper.updateCashBalance(POOR_ACCOUNT, Money.of("20.00"), 3, NOW));

            assertEquals(0, accountMapper.findById(POOR_ACCOUNT)
                    .getCashBalance().compareTo(Money.of("10.00")));
        }
    }

    @Nested
    @DisplayName("instruments")
    class Instruments {

        @Test
        void testFindBySymbol() {
            Instrument instrument = instrumentMapper.findBySymbol("ACME");

            assertNotNull(instrument);
            assertEquals("EQUITY", instrument.getAssetClass());
            assertEquals("USD", instrument.getCurrency());
            assertTrue(instrument.isTradable());
        }

        @Test
        @DisplayName("a suspended instrument is returned, and the domain decides what that means")
        void testFindBySymbol_NotTradable() {
            assertFalse(instrumentMapper.findBySymbol("DELIST").isTradable());
        }

        @Test
        void testFindBySymbol_Unknown() {
            assertNull(instrumentMapper.findBySymbol("NOPE"));
        }

        @Test
        @DisplayName("venue suffixes survive the round trip")
        void testFindBySymbol_VenueSuffix() {
            assertEquals("INFY.NS", instrumentMapper.findBySymbol("INFY.NS").getSymbol());
        }
    }

    @Nested
    @DisplayName("orders")
    class Orders {

        @Test
        void testInsertAndFindById() {
            Order order = newOrder("key-0000001");
            orderMapper.insert(order);

            Order stored = orderMapper.findById(order.getId());

            assertNotNull(stored);
            assertEquals(OrderStatus.NEW, stored.getStatus());
            assertEquals(OrderSide.BUY, stored.getSide());
            assertEquals(100, stored.getQuantity());
            assertEquals(0, stored.getPrice().compareTo(Money.of("25.50")));
            assertNull(stored.getExecutedPrice(), "a working order has not traded");
        }

        @Test
        @DisplayName("business rule 8 is the unique constraint, and here it is firing")
        void testInsert_DuplicateIdempotencyKey() {
            orderMapper.insert(newOrder("shared-key-01"));

            assertThrows(DuplicateKeyException.class,
                    () -> orderMapper.insert(newOrder("shared-key-01")));
        }

        @Test
        void testFindById_Unknown() {
            assertNull(orderMapper.findById(UUID.randomUUID()));
        }

        @Test
        @DisplayName("the blotter is newest first and hides nothing")
        void testFindByAccount() {
            Order older = Order.accept(UUID.randomUUID(), ACTIVE_ACCOUNT, "ACME", OrderSide.BUY, 1,
                    Money.of("1.00"), "key-old-0001", NOW.minusSeconds(600));
            Order newer = Order.accept(UUID.randomUUID(), ACTIVE_ACCOUNT, "ACME", OrderSide.SELL, 2,
                    Money.of("2.00"), "key-new-0001", NOW);
            orderMapper.insert(older);
            orderMapper.insert(newer);

            List<Order> history = orderMapper.findByAccount(ACTIVE_ACCOUNT, null, null, null);

            assertEquals(2, history.size());
            assertEquals(newer.getId(), history.getFirst().getId());
        }

        @Test
        void testFindByAccount_FilteredByStatus() {
            Order order = newOrder("key-0000002");
            orderMapper.insert(order);
            orderMapper.fillIfNew(order.getId(), Money.of("25.48"), NOW);
            orderMapper.insert(newOrder("key-0000003"));

            assertEquals(1, orderMapper.findByAccount(
                    ACTIVE_ACCOUNT, OrderStatus.FILLED, null, null).size());
            assertEquals(1, orderMapper.findByAccount(
                    ACTIVE_ACCOUNT, OrderStatus.NEW, null, null).size());
        }

        @Test
        void testFindByAccount_FilteredByDateRange() {
            orderMapper.insert(Order.accept(UUID.randomUUID(), ACTIVE_ACCOUNT, "ACME", OrderSide.BUY,
                    1, Money.of("1.00"), "key-0000004", Instant.parse("2026-01-01T00:00:00Z")));
            orderMapper.insert(Order.accept(UUID.randomUUID(), ACTIVE_ACCOUNT, "ACME", OrderSide.BUY,
                    1, Money.of("1.00"), "key-0000005", Instant.parse("2026-12-01T00:00:00Z")));

            assertEquals(1, orderMapper.findByAccount(ACTIVE_ACCOUNT, null,
                    Instant.parse("2026-06-01T00:00:00Z"), null).size());
            assertEquals(1, orderMapper.findByAccount(ACTIVE_ACCOUNT, null,
                    null, Instant.parse("2026-06-01T00:00:00Z")).size());
        }

        @Test
        @DisplayName("the guarded fill happens once, and a replay affects nothing")
        void testFillIfNew_IsIdempotent() {
            Order order = newOrder("key-0000006");
            orderMapper.insert(order);

            assertEquals(1, orderMapper.fillIfNew(order.getId(), Money.of("25.48"), NOW));
            assertEquals(0, orderMapper.fillIfNew(order.getId(), Money.of("99.99"), NOW));

            Order stored = orderMapper.findById(order.getId());
            assertEquals(OrderStatus.FILLED, stored.getStatus());
            assertEquals(0, stored.getExecutedPrice().compareTo(Money.of("25.48")),
                    "the replayed price must not have overwritten the real one");
        }

        @Test
        void testCancelIfNew() {
            Order order = newOrder("key-0000007");
            orderMapper.insert(order);

            assertEquals(1, orderMapper.cancelIfNew(order.getId()));
            assertEquals(OrderStatus.CANCELLED, orderMapper.findById(order.getId()).getStatus());
        }

        @Test
        @DisplayName("a filled order cannot be cancelled, and the database is what says so")
        void testCancelIfNew_AlreadyFilled() {
            Order order = newOrder("key-0000008");
            orderMapper.insert(order);
            orderMapper.fillIfNew(order.getId(), Money.of("25.48"), NOW);

            assertEquals(0, orderMapper.cancelIfNew(order.getId()));
            assertEquals(OrderStatus.FILLED, orderMapper.findById(order.getId()).getStatus());
        }

        @Test
        void testCancelIfNew_UnknownOrder() {
            assertEquals(0, orderMapper.cancelIfNew(UUID.randomUUID()));
        }
    }

    @Nested
    @DisplayName("positions")
    class Positions {

        @Test
        void testFind() {
            Position position = positionMapper.find(ACTIVE_ACCOUNT, "ACME");

            assertNotNull(position);
            assertEquals(100, position.getQuantity());
            assertEquals(0, position.getAverageCost().compareTo(Money.of("25.50")));
        }

        @Test
        void testFind_NotHeld() {
            assertNull(positionMapper.find(ACTIVE_ACCOUNT, "INFY.NS"));
        }

        @Test
        @DisplayName("a holding sold down to zero stays in the table and out of the response")
        void testFindByAccount_ExcludesEmptyPositions() {
            List<Position> positions = positionMapper.findByAccount(ACTIVE_ACCOUNT);

            assertEquals(1, positions.size());
            assertEquals("ACME", positions.getFirst().getSymbol());
            assertNotNull(positionMapper.find(ACTIVE_ACCOUNT, "AAPL"),
                    "the zero row is still there, it is only hidden from the API");
        }

        @Test
        void testUpsert_InsertsWhenAbsent() {
            positionMapper.upsert(ACTIVE_ACCOUNT, "INFY.NS", 40, Money.of("1580.25"));

            Position stored = positionMapper.find(ACTIVE_ACCOUNT, "INFY.NS");
            assertEquals(40, stored.getQuantity());
            assertEquals(0, stored.getAverageCost().compareTo(Money.of("1580.25")));
        }

        @Test
        void testUpsert_UpdatesWhenPresent() {
            positionMapper.upsert(ACTIVE_ACCOUNT, "ACME", 150, Money.of("26.00"));

            Position stored = positionMapper.find(ACTIVE_ACCOUNT, "ACME");
            assertEquals(150, stored.getQuantity());
            assertEquals(0, stored.getAverageCost().compareTo(Money.of("26.00")));
            assertEquals(1, positionMapper.findByAccount(ACTIVE_ACCOUNT).size(),
                    "the upsert must not have inserted a second row for the same key");
        }
    }
}

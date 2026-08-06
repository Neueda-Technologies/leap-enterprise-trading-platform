package com.tradingplatform.domain.model;

import com.tradingplatform.domain.TestFixtures;
import com.tradingplatform.domain.exception.InsufficientFundsException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static com.tradingplatform.domain.TestFixtures.account;
import static com.tradingplatform.domain.TestFixtures.money;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * The cash balance and the status of an account.
 *
 * <p>Named in the Sprint 5 acceptance criteria. It must be green.
 */
@DisplayName("Account")
class AccountTest {

    @Nested
    @DisplayName("status")
    class Status {

        @Test
        void testIsActive_ActiveAccount() {
            assertTrue(account("1000.00", AccountStatus.ACTIVE).isActive());
        }

        @Test
        void testIsActive_SuspendedAccount() {
            assertFalse(account("1000.00", AccountStatus.SUSPENDED).isActive());
        }

        @Test
        void testIsActive_ClosedAccount() {
            assertFalse(account("1000.00", AccountStatus.CLOSED).isActive());
        }
    }

    @Nested
    @DisplayName("debit")
    class Debit {

        @Test
        void testDebit_ReducesBalance() {
            Account account = account("1000.00");

            account.debit(money("250.50"));

            assertEquals(0, account.getCashBalance().compareTo(money("749.50")));
        }

        @Test
        @DisplayName("a debit that spends the balance exactly is allowed")
        void testDebit_ExactBalance() {
            Account account = account("1000.00");

            account.debit(money("1000.00"));

            assertEquals(0, account.getCashBalance().compareTo(Money.ZERO));
        }

        @Test
        @DisplayName("business rule 6: a debit larger than the balance is refused")
        void testDebit_InsufficientFunds() {
            Account account = account("100.00");

            InsufficientFundsException thrown =
                    assertThrows(InsufficientFundsException.class, () -> account.debit(money("100.01")));

            assertEquals("ORD-400", thrown.errorCode());
            assertEquals("Insufficient funds", thrown.getMessage());
        }

        @Test
        @DisplayName("a refused debit leaves the balance untouched")
        void testDebit_InsufficientFundsLeavesBalanceUnchanged() {
            Account account = account("100.00");

            assertThrows(InsufficientFundsException.class, () -> account.debit(money("500.00")));

            assertEquals(0, account.getCashBalance().compareTo(money("100.00")));
        }

        @Test
        void testDebit_ZeroAmountRejected() {
            Account account = account("100.00");

            assertThrows(IllegalArgumentException.class, () -> account.debit(BigDecimal.ZERO));
        }

        @Test
        @DisplayName("a negative debit would create money and is refused")
        void testDebit_NegativeAmountRejected() {
            Account account = account("100.00");

            assertThrows(IllegalArgumentException.class, () -> account.debit(money("-10.00")));
        }
    }

    @Nested
    @DisplayName("credit")
    class Credit {

        @Test
        void testCredit_IncreasesBalance() {
            Account account = account("1000.00");

            account.credit(money("2550.00"));

            assertEquals(0, account.getCashBalance().compareTo(money("3550.00")));
        }

        @Test
        void testCredit_ZeroAmountRejected() {
            Account account = account("100.00");

            assertThrows(IllegalArgumentException.class, () -> account.credit(BigDecimal.ZERO));
        }

        @Test
        void testCredit_NegativeAmountRejected() {
            Account account = account("100.00");

            assertThrows(IllegalArgumentException.class, () -> account.credit(money("-1.00")));
        }
    }

    @Nested
    @DisplayName("affordability")
    class Affordability {

        @Test
        void testCanAfford_LessThanBalance() {
            assertTrue(account("100.00").canAfford(money("99.99")));
        }

        @Test
        void testCanAfford_EqualToBalance() {
            assertTrue(account("100.00").canAfford(money("100.00")));
        }

        @Test
        void testCanAfford_MoreThanBalance() {
            assertFalse(account("100.00").canAfford(money("100.01")));
        }
    }

    @Nested
    @DisplayName("money handling")
    class MoneyHandling {

        @Test
        @DisplayName("a balance is held at two decimal places whatever scale it arrived at")
        void testBalanceIsNormalisedToTwoDecimalPlaces() {
            Account account = new Account(1L, "ACC-000001", "Priya Menon",
                    new BigDecimal("1000.5"), AccountStatus.ACTIVE, 0, TestFixtures.NOW);

            assertEquals(2, account.getCashBalance().scale());
        }

        @Test
        @DisplayName("repeated debits of 0.10 do not drift, which is why this is not a double")
        void testRepeatedSmallDebitsDoNotDrift() {
            Account account = account("100.00");

            for (int i = 0; i < 1000; i++) {
                account.debit(money("0.10"));
            }

            assertEquals(0, account.getCashBalance().compareTo(Money.ZERO));
        }
    }

    @Nested
    @DisplayName("optimistic locking")
    class OptimisticLocking {

        @Test
        @DisplayName("the version moves on only when persistence says the write was accepted")
        void testWriteAcceptedIncrementsVersion() {
            Account account = account("100.00");
            int before = account.getVersion();

            account.credit(money("1.00"));
            assertEquals(before, account.getVersion(), "a domain mutation alone does not move the version");

            account.writeAccepted(TestFixtures.NOW);
            assertEquals(before + 1, account.getVersion());
        }
    }

    @Test
    @DisplayName("toString carries no personal data and no balance")
    void testToStringOmitsConfidentialFields() {
        String rendered = account("24500.75").toString();

        assertFalse(rendered.contains("Priya"));
        assertFalse(rendered.contains("24500"));
    }
}

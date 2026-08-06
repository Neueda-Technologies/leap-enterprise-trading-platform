package com.tradingplatform.domain.model;

import com.tradingplatform.domain.exception.InsufficientFundsException;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Objects;

/**
 * A trading account and its cash balance.
 *
 * <p>This is the row that order placement contends on, so it carries an optimistic lock
 * {@link #version}. The domain does not perform the lock: it reports the version it was loaded at,
 * and the persistence layer updates with {@code WHERE version = :expected}. Zero rows affected means
 * another transaction won and the caller retries.
 *
 * <p>The class is mutable because it is an entity, not a value. {@link #debit} and {@link #credit}
 * move real money and are the only two ways the balance changes. Neither is permitted to leave the
 * balance negative, which is why the debit checks before it subtracts rather than subtracting and
 * inspecting the sign afterwards.
 *
 * <p>Two identifiers, and the difference matters. {@link #id} is the numeric surrogate key,
 * {@code accounts.id}. It is what the word {@code accountId} means everywhere in the REST contract,
 * in the JWT claim, in {@code orders.account_id} and in Kafka payloads. {@link #accountId} is the
 * string business reference, {@code accounts.account_id}, shown to customers as {@code ACC-000001}.
 * The names collide because the source domain model defines both. Do not rename either.
 */
public class Account {

    private final Long id;
    private final String accountId;
    private final String holderName;
    private BigDecimal cashBalance;
    private AccountStatus status;
    private int version;
    private Instant lastUpdated;

    public Account(Long id,
                   String accountId,
                   String holderName,
                   BigDecimal cashBalance,
                   AccountStatus status,
                   int version,
                   Instant lastUpdated) {
        this.id = Objects.requireNonNull(id, "id");
        this.accountId = Objects.requireNonNull(accountId, "accountId");
        this.holderName = Objects.requireNonNull(holderName, "holderName");
        this.cashBalance = Money.normalise(Objects.requireNonNull(cashBalance, "cashBalance"));
        this.status = Objects.requireNonNull(status, "status");
        this.version = version;
        this.lastUpdated = lastUpdated;
    }

    /**
     * True when the account may place or cancel orders. Business rule 2 is this method plus the
     * decision to raise {@code ACC-403} when it returns false.
     */
    public boolean isActive() {
        return status == AccountStatus.ACTIVE;
    }

    /**
     * True when the balance covers the amount. This is business rule 6 stated as a question. The
     * comparison is {@code >=}: an order that spends the balance exactly is affordable.
     */
    public boolean canAfford(BigDecimal amount) {
        return cashBalance.compareTo(Money.normalise(amount)) >= 0;
    }

    /**
     * Removes cash from the account.
     *
     * @throws IllegalArgumentException    when the amount is zero or negative. A debit of a negative
     *                                     amount is a credit written by accident, and silently
     *                                     honouring it would let a bug create money.
     * @throws InsufficientFundsException  when the balance does not cover the amount. Checked before
     *                                     the subtraction, so a refused debit leaves the balance
     *                                     untouched.
     */
    public void debit(BigDecimal amount) {
        BigDecimal value = requirePositive(amount, "debit");
        if (!canAfford(value)) {
            throw new InsufficientFundsException(value, cashBalance);
        }
        cashBalance = Money.normalise(cashBalance.subtract(value));
    }

    /**
     * Adds cash to the account.
     *
     * @throws IllegalArgumentException when the amount is zero or negative.
     */
    public void credit(BigDecimal amount) {
        BigDecimal value = requirePositive(amount, "credit");
        cashBalance = Money.normalise(cashBalance.add(value));
    }

    private static BigDecimal requirePositive(BigDecimal amount, String operation) {
        Objects.requireNonNull(amount, operation + " amount");
        BigDecimal value = Money.normalise(amount);
        if (!Money.isPositive(value)) {
            throw new IllegalArgumentException("A " + operation + " must be greater than zero");
        }
        return value;
    }

    /** Suspends or closes the account. Reversible only for {@code SUSPENDED}. */
    public void changeStatus(AccountStatus newStatus) {
        this.status = Objects.requireNonNull(newStatus, "status");
    }

    /** The numeric surrogate key, {@code accounts.id}. */
    public Long getId() {
        return id;
    }

    /** The string business reference, {@code accounts.account_id}, for example {@code ACC-000001}. */
    public String getAccountId() {
        return accountId;
    }

    public String getHolderName() {
        return holderName;
    }

    public BigDecimal getCashBalance() {
        return cashBalance;
    }

    public AccountStatus getStatus() {
        return status;
    }

    /** The optimistic lock version this instance was loaded at. */
    public int getVersion() {
        return version;
    }

    public Instant getLastUpdated() {
        return lastUpdated;
    }

    /**
     * Records that persistence accepted a write and moved the row on. Called by the repository after
     * a successful guarded update, so that a second write in the same request uses the new version.
     */
    public void writeAccepted(Instant writtenAt) {
        this.version = this.version + 1;
        this.lastUpdated = writtenAt;
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        return other instanceof Account account && id.equals(account.id);
    }

    @Override
    public int hashCode() {
        return id.hashCode();
    }

    /**
     * Identity and status only. The holder name is personal data and the balance is confidential,
     * so neither belongs in a string that will end up in a log line.
     */
    @Override
    public String toString() {
        return "Account[id=" + id + ", status=" + status + ", version=" + version + "]";
    }
}

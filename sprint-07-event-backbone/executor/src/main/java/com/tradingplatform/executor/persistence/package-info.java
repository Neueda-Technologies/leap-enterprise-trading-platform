/**
 * Persistence: the statements this service runs against the Sprint 3 schema.
 *
 * <p>Single responsibility: read the order, the account and the position, and write the three
 * changes that settle an order. It decides nothing and holds no rule.
 *
 * <p>Every statement here returns the number of rows it affected, and the caller reads that number.
 * A method that returns {@code void} has thrown away the only evidence that anything happened, and
 * the two statements this service depends on most are the ones whose whole meaning is in that
 * count: the guarded status transition, where zero rows means another delivery got there first, and
 * the cash update under the optimistic lock, where zero rows means another writer moved first.
 *
 * <p>Every value that comes from outside is bound as a parameter. The rule from Sprint 6 does not
 * relax because the caller is a Kafka consumer rather than a controller: a symbol that arrived on a
 * topic is still a value somebody else chose.
 *
 * <p>The service connects as the least-privileged application role, not as the schema owner.
 */
package com.tradingplatform.executor.persistence;

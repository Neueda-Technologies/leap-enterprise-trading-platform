/**
 * The persistence layer: MyBatis mapper interfaces and nothing else.
 *
 * <p>Single responsibility: run one statement and map its result. A mapper decides nothing. It does
 * not know why it is being called, it does not catch the exception it raises, and it does not know
 * that HTTP exists.
 *
 * <p>Every value that arrives from outside the service is bound with {@code #{}}. That becomes a
 * JDBC bind parameter: the driver sends the statement and the value separately and no value the
 * caller sends can change what the statement does. {@code ${}} is a string substitution performed
 * before the driver sees anything, and it is how an injection reaches the database.
 *
 * <p>A statement that changes a row returns the number of rows it changed. A mapper method that
 * returns {@code void} has thrown away the only evidence that the optimistic lock held.
 *
 * <p>Statements live in XML under {@code src/main/resources/mapper/} or in annotations on these
 * interfaces. Pick one and stay with it.
 */
package com.tradingplatform.tradeapi.repository;

/**
 * Configuration: the beans and the bound properties the service needs to start.
 *
 * <p>Single responsibility: assemble things, and hold no logic worth testing. Filter registration,
 * type handlers, a clock, and the typed holders for the properties in {@code application.yml}
 * belong here.
 *
 * <p>Every value that differs between a laptop and a container is read from an environment variable
 * with a default that works under Docker Compose. No secret is committed, including a development
 * one: a signing secret in a properties file is a signing secret in the history of the repository
 * forever.
 */
package com.tradingplatform.tradeapi.config;

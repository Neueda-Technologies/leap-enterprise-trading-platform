package com.tradingplatform.tradeapi.config;

import org.apache.ibatis.mapping.DatabaseIdProvider;
import org.apache.ibatis.mapping.VendorDatabaseIdProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.Properties;

/**
 * Tells MyBatis which database it is talking to, so that a statement can have a dialect-specific
 * variant.
 *
 * <p>Exactly one statement needs this: the position upsert. Postgres resolves it with
 * {@code INSERT ... ON CONFLICT}, which is the correct single-statement form against the target
 * database and is what runs in every environment that matters. H2, which the mapper tests use so
 * they can run in a second without Docker, has no {@code ON CONFLICT ... DO UPDATE} and needs
 * {@code MERGE INTO ... KEY(...)}.
 *
 * <p>The alternative was to write the upsert portably, as an update followed by an insert when the
 * update affected nothing. That is worse: two concurrent fills on the same account and symbol both
 * find no row to update and both insert, and one of them fails on the primary key having already
 * lost the value it was carrying. Keeping the correct statement and naming the test dialect
 * explicitly is the smaller compromise, and the H2 variant is labelled in the mapper as what it is.
 *
 * <p>Do not use this to paper over a second database in production. One operational database, one
 * dialect.
 */
@Configuration
public class MyBatisConfig {

    @Bean
    public DatabaseIdProvider databaseIdProvider() {
        VendorDatabaseIdProvider provider = new VendorDatabaseIdProvider();
        Properties aliases = new Properties();
        aliases.setProperty("PostgreSQL", "postgresql");
        aliases.setProperty("H2", "h2");
        provider.setProperties(aliases);
        return provider;
    }
}

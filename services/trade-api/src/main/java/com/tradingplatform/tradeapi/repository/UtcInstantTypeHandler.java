package com.tradingplatform.tradeapi.repository;

import org.apache.ibatis.type.BaseTypeHandler;
import org.apache.ibatis.type.JdbcType;
import org.apache.ibatis.type.MappedTypes;

import java.sql.CallableStatement;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;

/**
 * Maps {@code java.time.Instant} to a {@code TIMESTAMP WITHOUT TIME ZONE} column, in UTC.
 *
 * <p>The operational schema stores time as {@code TIMESTAMP}, which carries no zone. MyBatis's own
 * Instant handler bridges the gap through {@code java.sql.Timestamp}, and that conversion uses the
 * JVM default zone. The consequence is that the same row read on a laptop in Dublin during British
 * Summer Time and on a container running UTC produces instants an hour apart, and the difference
 * appears in an API response, in a Kafka payload, and in the analytical store.
 *
 * <p>This handler removes the ambiguity by fixing the interpretation at UTC in both directions. It
 * is the smallest correct fix given a schema that is already specified. The larger fix, and the one
 * to make in any schema you design yourself, is {@code TIMESTAMPTZ}: a trading platform spanning
 * Dublin, Boston and Bangalore has no single local time, and a column that does not say which zone
 * it means is a defect waiting for a clock change.
 */
@MappedTypes(Instant.class)
public class UtcInstantTypeHandler extends BaseTypeHandler<Instant> {

    @Override
    public void setNonNullParameter(PreparedStatement ps, int i, Instant parameter, JdbcType jdbcType)
            throws SQLException {
        ps.setObject(i, LocalDateTime.ofInstant(parameter, ZoneOffset.UTC));
    }

    @Override
    public Instant getNullableResult(ResultSet rs, String columnName) throws SQLException {
        return toInstant(rs.getObject(columnName, LocalDateTime.class));
    }

    @Override
    public Instant getNullableResult(ResultSet rs, int columnIndex) throws SQLException {
        return toInstant(rs.getObject(columnIndex, LocalDateTime.class));
    }

    @Override
    public Instant getNullableResult(CallableStatement cs, int columnIndex) throws SQLException {
        return toInstant(cs.getObject(columnIndex, LocalDateTime.class));
    }

    private static Instant toInstant(LocalDateTime value) {
        return value == null ? null : value.toInstant(ZoneOffset.UTC);
    }
}

package com.tradingplatform.tradeapi.repository;

import org.apache.ibatis.type.BaseTypeHandler;
import org.apache.ibatis.type.JdbcType;
import org.apache.ibatis.type.MappedTypes;

import java.sql.CallableStatement;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.UUID;

/**
 * Maps {@code java.util.UUID} to the {@code UUID} column type.
 *
 * <p>MyBatis registers handlers for the primitives, the JDK date and time types and enumerations, but
 * not for {@code UUID}. Without this, {@code orders.id} binds as a string and Postgres refuses the
 * comparison with a {@code uuid} column.
 *
 * <p>{@code setObject} with the {@code UUID} instance rather than {@code setString} matters. The
 * Postgres driver understands the type and sends it as a binary uuid, so the query plan uses the
 * primary key index instead of falling back to a cast.
 */
@MappedTypes(UUID.class)
public class UuidTypeHandler extends BaseTypeHandler<UUID> {

    @Override
    public void setNonNullParameter(PreparedStatement ps, int i, UUID parameter, JdbcType jdbcType)
            throws SQLException {
        ps.setObject(i, parameter);
    }

    @Override
    public UUID getNullableResult(ResultSet rs, String columnName) throws SQLException {
        return rs.getObject(columnName, UUID.class);
    }

    @Override
    public UUID getNullableResult(ResultSet rs, int columnIndex) throws SQLException {
        return rs.getObject(columnIndex, UUID.class);
    }

    @Override
    public UUID getNullableResult(CallableStatement cs, int columnIndex) throws SQLException {
        return cs.getObject(columnIndex, UUID.class);
    }
}

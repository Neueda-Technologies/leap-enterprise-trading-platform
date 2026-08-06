import { Inject, Injectable } from '@nestjs/common';
import { Pool, QueryResult } from 'pg';
import { PG_POOL } from '../database/database.constants';

export interface RefreshTokenRow {
  id: string;
  user_id: string;
  consumed_on: Date | null;
  revoked_on: Date | null;
  expires_on: Date;
}

/**
 * Storage for refresh tokens.
 *
 * The token itself never reaches this table. Only a SHA-256 of it is stored, so
 * a database dump is not a set of live sessions. SHA-256 rather than argon2 here
 * because the token is 256 bits of randomness, not a human-chosen password:
 * there is no dictionary to slow an attacker down against.
 */
@Injectable()
export class RefreshTokenRepository {
  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  async create(userId: string, tokenHash: string, expiresOn: Date): Promise<void> {
    await this.pool.query(
      `INSERT INTO auth.refresh_tokens (user_id, token_hash, expires_on)
            VALUES ($1::uuid, $2, $3)`,
      [userId, tokenHash, expiresOn],
    );
  }

  async findByHash(tokenHash: string): Promise<RefreshTokenRow | null> {
    const result: QueryResult<RefreshTokenRow> = await this.pool.query(
      `SELECT id, user_id, consumed_on, revoked_on, expires_on
         FROM auth.refresh_tokens
        WHERE token_hash = $1`,
      [tokenHash],
    );
    return result.rows.length === 1 ? result.rows[0] : null;
  }

  /**
   * Marks a token consumed, and reports whether this call was the one that did it.
   *
   * The guard is in the WHERE clause, not in application code. Two refresh
   * requests arriving with the same token at the same moment both read an
   * unconsumed row; only one of them can update it, and the other gets zero rows
   * and is treated as a replay.
   */
  async consume(id: string): Promise<boolean> {
    const result = await this.pool.query(
      `UPDATE auth.refresh_tokens
          SET consumed_on = NOW()
        WHERE id = $1::uuid
          AND consumed_on IS NULL
          AND revoked_on IS NULL
          AND expires_on > NOW()`,
      [id],
    );
    return (result.rowCount ?? 0) > 0;
  }

  /**
   * Revokes every live token for a user. The response to a replayed token.
   *
   * A refresh token presented twice means one of the two presenters is not the
   * user. There is no way to tell which, so the whole chain goes and both are
   * made to log in again.
   */
  async revokeAllForUser(userId: string): Promise<number> {
    const result = await this.pool.query(
      `UPDATE auth.refresh_tokens
          SET revoked_on = NOW()
        WHERE user_id = $1::uuid
          AND revoked_on IS NULL
          AND consumed_on IS NULL`,
      [userId],
    );
    return result.rowCount ?? 0;
  }
}

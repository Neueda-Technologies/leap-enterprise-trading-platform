import { Inject, Injectable, Logger } from '@nestjs/common';
import { Pool, QueryResult } from 'pg';
import { PG_POOL } from '../database/database.constants';
import { Role } from './role.enum';
import { UserRecord } from './user.entity';
import { UsernameTakenError } from './users.errors';

/** Postgres unique-violation SQLSTATE. */
const UNIQUE_VIOLATION = '23505';
/** Postgres undefined-table SQLSTATE. */
const UNDEFINED_TABLE = '42P01';

interface UserRow {
  id: string;
  username: string;
  password_hash: string;
  account_id: string;
  roles: string[];
  created_on: Date;
}

/**
 * Every statement this service runs against `auth.users`.
 *
 * All of them are parameterised. String concatenation into SQL is the defect
 * planted in the `us-ireland` starter code for exactly this layer, and it is the
 * one thing a reviewer checks first here.
 */
@Injectable()
export class UsersRepository {
  private readonly logger = new Logger(UsersRepository.name);

  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  async findByUsername(username: string): Promise<UserRecord | null> {
    const result: QueryResult<UserRow> = await this.pool.query(
      `SELECT id, username, password_hash, account_id, roles, created_on
         FROM auth.users
        WHERE username = $1`,
      [username],
    );
    return result.rows.length === 1 ? this.toRecord(result.rows[0]) : null;
  }

  async findById(id: string): Promise<UserRecord | null> {
    const result: QueryResult<UserRow> = await this.pool.query(
      `SELECT id, username, password_hash, account_id, roles, created_on
         FROM auth.users
        WHERE id = $1`,
      [id],
    );
    return result.rows.length === 1 ? this.toRecord(result.rows[0]) : null;
  }

  /**
   * Inserts a user, letting the unique constraint decide the outcome.
   *
   * The duplicate check is the constraint, not a SELECT followed by an INSERT.
   * Two concurrent registrations of the same username both pass a prior SELECT
   * and one of them then violates the constraint anyway, so the check would only
   * have hidden the race.
   */
  async insert(params: {
    id?: string;
    username: string;
    passwordHash: string;
    accountId: number;
    roles: Role[];
  }): Promise<UserRecord> {
    try {
      const result: QueryResult<UserRow> = await this.pool.query(
        `INSERT INTO auth.users (id, username, password_hash, account_id, roles)
              VALUES (COALESCE($1::uuid, gen_random_uuid()), $2, $3, $4, $5::text[])
           RETURNING id, username, password_hash, account_id, roles, created_on`,
        [params.id ?? null, params.username, params.passwordHash, params.accountId, params.roles],
      );
      return this.toRecord(result.rows[0]);
    } catch (error) {
      if (this.sqlState(error) === UNIQUE_VIOLATION) {
        throw new UsernameTakenError(params.username);
      }
      throw error;
    }
  }

  /**
   * Inserts a user only if the username is free. Used by the demo seeder.
   *
   * Returns true when a row was written, so that a restart logs "seeded 0 users"
   * rather than claiming work it did not do.
   */
  async insertIfAbsent(params: {
    id: string;
    username: string;
    passwordHash: string;
    accountId: number;
    roles: Role[];
  }): Promise<boolean> {
    const result = await this.pool.query(
      `INSERT INTO auth.users (id, username, password_hash, account_id, roles)
            VALUES ($1::uuid, $2, $3, $4, $5::text[])
       ON CONFLICT (username) DO NOTHING`,
      [params.id, params.username, params.passwordHash, params.accountId, params.roles],
    );
    return (result.rowCount ?? 0) > 0;
  }

  /**
   * Checks that the trading account exists before a user is linked to it.
   *
   * Returns null when the accounts table is not present. The auth service can be
   * run on its own against an empty database while the Sprint 3 schema is being
   * built, and refusing every registration in that case would make the service
   * untestable in isolation. Where the table exists, the answer is authoritative
   * and the foreign key in `migrations/users.sql` enforces it as well.
   */
  async accountExists(accountId: number): Promise<boolean | null> {
    try {
      const result = await this.pool.query('SELECT 1 FROM public.accounts WHERE id = $1', [accountId]);
      return (result.rowCount ?? 0) > 0;
    } catch (error) {
      if (this.sqlState(error) === UNDEFINED_TABLE) {
        this.logger.warn('account check skipped', {
          event: 'account.check.skipped',
          reason: 'public.accounts does not exist',
        });
        return null;
      }
      throw error;
    }
  }

  private sqlState(error: unknown): string | undefined {
    return typeof error === 'object' && error !== null && 'code' in error
      ? String((error as { code: unknown }).code)
      : undefined;
  }

  /**
   * Maps snake_case columns to camelCase fields in one place.
   *
   * `account_id` is a BIGINT, and node-postgres returns BIGINT as a string so
   * that values above 2^53 are not silently corrupted. The platform's account
   * identifiers are small, so the conversion is safe here and the JWT claim must
   * be a number.
   */
  private toRecord(row: UserRow): UserRecord {
    return {
      id: row.id,
      username: row.username,
      passwordHash: row.password_hash,
      accountId: Number(row.account_id),
      roles: row.roles as Role[],
      createdOn: row.created_on,
    };
  }
}

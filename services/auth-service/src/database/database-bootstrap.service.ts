import { Inject, Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { Pool } from 'pg';
import { AuthConfig } from '../config/configuration';
import { PG_POOL } from './database.constants';

/**
 * Applies `migrations/users.sql` at boot.
 *
 * Two things make this safe to run on every start. The file is idempotent:
 * every statement is `IF NOT EXISTS` or guarded by a `DO` block. And it runs in
 * one transaction, so a half-applied schema is not a state the service can be
 * left in.
 *
 * Set AUTH_RUN_MIGRATIONS=false where the infrastructure applies the file
 * instead, which is what a deployment connecting as a role without DDL rights
 * must do. The README covers both routes.
 *
 * Runs in onModuleInit rather than onApplicationBootstrap so that it completes
 * before the demo-user seeder, which runs one lifecycle phase later.
 */
@Injectable()
export class DatabaseBootstrapService implements OnModuleInit {
  private readonly logger = new Logger(DatabaseBootstrapService.name);

  constructor(
    @Inject(PG_POOL) private readonly pool: Pool,
    private readonly config: ConfigService<AuthConfig, true>,
  ) {}

  async onModuleInit(): Promise<void> {
    if (!this.config.get('bootstrap', { infer: true }).runMigrations) {
      this.logger.log('schema bootstrap skipped', { event: 'migration.skipped', reason: 'AUTH_RUN_MIGRATIONS=false' });
      return;
    }

    const sql = this.readMigration();
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query('COMMIT');
      this.logger.log('schema bootstrap applied', { event: 'migration.applied', file: 'users.sql' });
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Resolves the DDL next to the service, not next to the compiled output.
   *
   * `__dirname` is `src/database` under ts-node and `dist/database` after a
   * build, and both are two levels below the service root, so one path works in
   * both. The working-directory fallback covers a process started from an
   * unusual place.
   */
  private readMigration(): string {
    const candidates = [
      join(__dirname, '..', '..', 'migrations', 'users.sql'),
      join(process.cwd(), 'migrations', 'users.sql'),
    ];

    for (const candidate of candidates) {
      try {
        return readFileSync(candidate, 'utf8');
      } catch {
        continue;
      }
    }

    throw new Error(`migrations/users.sql not found. Looked in: ${candidates.join(', ')}`);
  }
}

import { Global, Inject, Logger, Module, OnApplicationShutdown } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool } from 'pg';
import { AuthConfig } from '../config/configuration';
import { PG_POOL } from './database.constants';
import { DatabaseBootstrapService } from './database-bootstrap.service';

/**
 * Owns the single connection pool and the boot-time schema bootstrap.
 *
 * Global because two feature modules need the pool and neither of them should
 * have to know how it is built. One pool per process: a pool per repository
 * multiplies open connections by the number of repositories and exhausts
 * Postgres long before it exhausts the service.
 */
@Global()
@Module({
  providers: [
    {
      provide: PG_POOL,
      inject: [ConfigService],
      useFactory: (config: ConfigService<AuthConfig, true>): Pool => {
        const database = config.get('database', { infer: true });
        return new Pool(
          database.connectionString
            ? { connectionString: database.connectionString, max: database.maxConnections }
            : {
                host: database.host,
                port: database.port,
                user: database.user,
                password: database.password,
                database: database.database,
                max: database.maxConnections,
              },
        );
      },
    },
    DatabaseBootstrapService,
  ],
  exports: [PG_POOL],
})
export class DatabaseModule implements OnApplicationShutdown {
  private readonly logger = new Logger(DatabaseModule.name);

  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  /** Closes the pool so that a container stop does not leave idle backends behind. */
  async onApplicationShutdown(): Promise<void> {
    await this.pool.end().catch((error: Error) => this.logger.warn('pool close failed', { error: error.message }));
  }
}

import { Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AuthConfig } from '../config/configuration';
import { DEMO_PASSWORD, DEMO_USERS } from './demo-users';
import { PasswordService } from './password.service';
import { UsersRepository } from './users.repository';

/**
 * Seeds `demo1` to `demo5` when AUTH_SEED_DEMO_USERS is true.
 *
 * Idempotent: the insert is `ON CONFLICT (username) DO NOTHING`, so restarting
 * the container twenty times still leaves five users, and a password a
 * participant changed by hand is not overwritten.
 *
 * Runs in onApplicationBootstrap, one lifecycle phase after the schema
 * bootstrap in onModuleInit, so the table it writes to exists.
 */
@Injectable()
export class DemoUserSeeder implements OnApplicationBootstrap {
  private readonly logger = new Logger(DemoUserSeeder.name);

  constructor(
    private readonly users: UsersRepository,
    private readonly passwords: PasswordService,
    private readonly config: ConfigService<AuthConfig, true>,
  ) {}

  async onApplicationBootstrap(): Promise<void> {
    if (!this.config.get('bootstrap', { infer: true }).seedDemoUsers) {
      return;
    }

    let inserted = 0;
    for (const demo of DEMO_USERS) {
      // Hashed per user rather than once, because argon2 salts each hash and
      // five identical hashes in a table would tell a reader the passwords match.
      const passwordHash = await this.passwords.hash(DEMO_PASSWORD);
      const written = await this.users.insertIfAbsent({
        id: demo.id,
        username: demo.username,
        passwordHash,
        accountId: demo.accountId,
        roles: demo.roles,
      });
      if (written) {
        inserted += 1;
      }
    }

    this.logger.log('demo users seeded', {
      event: 'seed.completed',
      requested: DEMO_USERS.length,
      inserted,
      alreadyPresent: DEMO_USERS.length - inserted,
    });
  }
}

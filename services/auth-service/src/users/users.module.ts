import { Module } from '@nestjs/common';
import { DemoUserSeeder } from './demo-user.seeder';
import { PasswordService } from './password.service';
import { UsersRepository } from './users.repository';
import { UsersService } from './users.service';

/**
 * Everything that knows what a user is.
 *
 * It exports the service, not the repository. A second feature module that can
 * reach the repository directly will eventually write a user without hashing a
 * password, and the rule that only this module hashes will have been quietly
 * lost.
 */
@Module({
  providers: [UsersRepository, UsersService, PasswordService, DemoUserSeeder],
  exports: [UsersService, PasswordService],
})
export class UsersModule {}

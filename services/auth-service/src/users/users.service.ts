import { Injectable, Logger } from '@nestjs/common';
import { InvalidInputException, RegistrationConflictException } from '../common/errors/auth.exceptions';
import { RegisterDto } from './dto/register.dto';
import { PasswordService } from './password.service';
import { Role } from './role.enum';
import { UserRecord } from './user.entity';
import { UsersRepository } from './users.repository';
import { UsernameTakenError } from './users.errors';

/**
 * User creation and credential verification.
 *
 * The controller does not touch the repository and the repository does not know
 * what an HTTP status is. Everything that has to hold true about a user, the
 * account link, the hashing, the role assignment, holds here.
 */
@Injectable()
export class UsersService {
  private readonly logger = new Logger(UsersService.name);

  constructor(
    private readonly users: UsersRepository,
    private readonly passwords: PasswordService,
  ) {}

  /**
   * Creates a user against an existing trading account.
   *
   * Roles from the request body are dropped. The contract lists the field, and
   * an honest implementation of it on a public route is to ignore it: this
   * endpoint has no caller identity, so there is nobody to authorise an ADMIN
   * request against.
   */
  async register(dto: RegisterDto): Promise<UserRecord> {
    if (dto.roles) {
      this.logger.warn('roles ignored on public registration', {
        event: 'register.roles.ignored',
        username: dto.username,
      });
    }

    const accountExists = await this.users.accountExists(dto.accountId);
    if (accountExists === false) {
      // The contract treats an unknown account as a validation failure, so it is
      // VAL-422 rather than the AUTH-409 a taken username gets.
      throw new InvalidInputException();
    }

    const passwordHash = await this.passwords.hash(dto.password);

    try {
      const user = await this.users.insert({
        username: dto.username,
        passwordHash,
        accountId: dto.accountId,
        roles: [Role.CUSTOMER],
      });
      this.logger.log('user registered', {
        event: 'register.succeeded',
        userId: user.id,
        accountId: user.accountId,
      });
      return user;
    } catch (error) {
      if (error instanceof UsernameTakenError) {
        this.logger.warn('registration rejected', { event: 'register.conflict', username: dto.username });
        throw new RegistrationConflictException();
      }
      throw error;
    }
  }

  async findById(id: string): Promise<UserRecord | null> {
    return this.users.findById(id);
  }

  /**
   * Returns the user when the password matches, and null in every other case.
   *
   * Both branches do one argon2 verification. An unknown username verifies
   * against a hash of a random string, which fails, and takes the same time as a
   * real check. Skipping that call is the classic user-enumeration defect: the
   * bodies match, the timings do not.
   */
  async validateCredentials(username: string, password: string): Promise<UserRecord | null> {
    const user = await this.users.findByUsername(username);

    if (!user) {
      await this.passwords.verifyDummy(password);
      return null;
    }

    const matches = await this.passwords.verify(user.passwordHash, password);
    return matches ? user : null;
  }
}

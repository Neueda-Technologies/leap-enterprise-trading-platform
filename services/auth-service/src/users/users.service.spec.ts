import { InvalidInputException, RegistrationConflictException } from '../common/errors/auth.exceptions';
import { PasswordService } from './password.service';
import { Role } from './role.enum';
import { UserRecord } from './user.entity';
import { UsersRepository } from './users.repository';
import { UsernameTakenError } from './users.errors';
import { UsersService } from './users.service';

const STORED: UserRecord = {
  id: '8f14e45f-ceea-4c1b-9d3b-1a2b3c4d5e6f',
  username: 'demo1',
  passwordHash: '$argon2id$v=19$m=19456,t=2,p=1$c2FsdA$aGFzaA',
  accountId: 1,
  roles: [Role.CUSTOMER],
  createdOn: new Date('2026-10-05T08:00:00Z'),
};

describe('UsersService', () => {
  let repository: {
    findByUsername: jest.Mock;
    findById: jest.Mock;
    insert: jest.Mock;
    accountExists: jest.Mock;
  };
  let passwords: { hash: jest.Mock; verify: jest.Mock; verifyDummy: jest.Mock };
  let users: UsersService;

  beforeEach(() => {
    repository = {
      findByUsername: jest.fn(),
      findById: jest.fn(),
      insert: jest.fn().mockResolvedValue(STORED),
      accountExists: jest.fn().mockResolvedValue(true),
    };
    passwords = {
      hash: jest.fn().mockResolvedValue(STORED.passwordHash),
      verify: jest.fn(),
      verifyDummy: jest.fn().mockResolvedValue(false),
    };
    users = new UsersService(repository as unknown as UsersRepository, passwords as unknown as PasswordService);
  });

  describe('register', () => {
    it('hashes the password and never passes the plaintext to the repository', async () => {
      await users.register({ username: 'demo1', password: 'Trainee#2026', accountId: 1 });

      expect(passwords.hash).toHaveBeenCalledWith('Trainee#2026');
      expect(repository.insert).toHaveBeenCalledWith({
        username: 'demo1',
        passwordHash: STORED.passwordHash,
        accountId: 1,
        roles: [Role.CUSTOMER],
      });
    });

    it('ignores a self-declared role and always assigns CUSTOMER', async () => {
      await users.register({
        username: 'attacker',
        password: 'Trainee#2026',
        accountId: 1,
        roles: [Role.ADMIN],
      });

      expect(repository.insert).toHaveBeenCalledWith(expect.objectContaining({ roles: [Role.CUSTOMER] }));
    });

    it('rejects an unknown trading account as invalid input', async () => {
      repository.accountExists.mockResolvedValue(false);

      await expect(
        users.register({ username: 'demo1', password: 'Trainee#2026', accountId: 999 }),
      ).rejects.toBeInstanceOf(InvalidInputException);
      expect(repository.insert).not.toHaveBeenCalled();
    });

    it('registers when the account table is absent and the check cannot be made', async () => {
      repository.accountExists.mockResolvedValue(null);

      await expect(users.register({ username: 'demo1', password: 'Trainee#2026', accountId: 1 })).resolves.toBe(STORED);
    });

    it('maps a taken username to the AUTH-409 conflict', async () => {
      repository.insert.mockRejectedValue(new UsernameTakenError('demo1'));

      await expect(users.register({ username: 'demo1', password: 'Trainee#2026', accountId: 1 })).rejects.toBeInstanceOf(
        RegistrationConflictException,
      );
    });
  });

  describe('validateCredentials', () => {
    it('returns the user when the password matches', async () => {
      repository.findByUsername.mockResolvedValue(STORED);
      passwords.verify.mockResolvedValue(true);

      await expect(users.validateCredentials('demo1', 'Trainee#2026')).resolves.toBe(STORED);
    });

    it('returns null when the password does not match', async () => {
      repository.findByUsername.mockResolvedValue(STORED);
      passwords.verify.mockResolvedValue(false);

      await expect(users.validateCredentials('demo1', 'wrong-password')).resolves.toBeNull();
    });

    it('verifies a dummy hash when the username is unknown, so the two paths cost the same', async () => {
      repository.findByUsername.mockResolvedValue(null);

      await expect(users.validateCredentials('nobody', 'Trainee#2026')).resolves.toBeNull();
      expect(passwords.verifyDummy).toHaveBeenCalledWith('Trainee#2026');
    });
  });
});

import { UnauthorisedException } from '../common/errors/auth.exceptions';
import { TokenService } from '../tokens/token.service';
import { Role } from '../users/role.enum';
import { UserRecord } from '../users/user.entity';
import { UsersService } from '../users/users.service';
import { AuthService } from './auth.service';

const USER: UserRecord = {
  id: '8f14e45f-ceea-4c1b-9d3b-1a2b3c4d5e6f',
  username: 'demo1',
  passwordHash: '$argon2id$v=19$m=19456,t=2,p=1$c2FsdA$aGFzaA',
  accountId: 1,
  roles: [Role.CUSTOMER],
  createdOn: new Date('2026-10-05T08:00:00Z'),
};

describe('AuthService', () => {
  let users: { validateCredentials: jest.Mock; findById: jest.Mock; register: jest.Mock };
  let tokens: { issueAccessToken: jest.Mock; issueRefreshToken: jest.Mock; consumeRefreshToken: jest.Mock };
  let auth: AuthService;

  beforeEach(() => {
    users = { validateCredentials: jest.fn(), findById: jest.fn(), register: jest.fn() };
    tokens = {
      issueAccessToken: jest.fn().mockResolvedValue({ token: 'access.token.value', expiresIn: 900 }),
      issueRefreshToken: jest.fn().mockResolvedValue('f'.repeat(64)),
      consumeRefreshToken: jest.fn(),
    };
    auth = new AuthService(users as unknown as UsersService, tokens as unknown as TokenService);
  });

  describe('login', () => {
    it('returns a token pair for correct credentials', async () => {
      users.validateCredentials.mockResolvedValue(USER);

      await expect(auth.login({ username: 'demo1', password: 'Trainee#2026' })).resolves.toEqual({
        accessToken: 'access.token.value',
        refreshToken: 'f'.repeat(64),
        tokenType: 'Bearer',
        expiresIn: 900,
      });

      expect(tokens.issueAccessToken).toHaveBeenCalledWith({
        id: USER.id,
        username: 'demo1',
        accountId: 1,
        roles: [Role.CUSTOMER],
      });
    });

    it('fails identically for an unknown username and for a wrong password', async () => {
      users.validateCredentials.mockResolvedValue(null);

      const unknownUser = await auth.login({ username: 'nobody', password: 'Trainee#2026' }).catch((e: Error) => e);
      const wrongPassword = await auth.login({ username: 'demo1', password: 'wrong-password' }).catch((e: Error) => e);

      expect(unknownUser).toBeInstanceOf(UnauthorisedException);
      expect(wrongPassword).toBeInstanceOf(UnauthorisedException);
      expect((unknownUser as UnauthorisedException).getStatus()).toBe(
        (wrongPassword as UnauthorisedException).getStatus(),
      );
      expect((unknownUser as UnauthorisedException).getResponse()).toEqual(
        (wrongPassword as UnauthorisedException).getResponse(),
      );
    });

    it('issues no token when the credentials fail', async () => {
      users.validateCredentials.mockResolvedValue(null);

      await expect(auth.login({ username: 'demo1', password: 'wrong-password' })).rejects.toBeInstanceOf(
        UnauthorisedException,
      );
      expect(tokens.issueAccessToken).not.toHaveBeenCalled();
      expect(tokens.issueRefreshToken).not.toHaveBeenCalled();
    });
  });

  describe('refresh', () => {
    it('consumes the presented token and issues a new pair', async () => {
      tokens.consumeRefreshToken.mockResolvedValue(USER.id);
      users.findById.mockResolvedValue(USER);

      const pair = await auth.refresh({ refreshToken: 'a'.repeat(64) });

      expect(tokens.consumeRefreshToken).toHaveBeenCalledWith('a'.repeat(64));
      expect(pair.refreshToken).toBe('f'.repeat(64));
      expect(pair.tokenType).toBe('Bearer');
    });

    it('rejects when the token service refuses the token', async () => {
      tokens.consumeRefreshToken.mockRejectedValue(new UnauthorisedException());

      await expect(auth.refresh({ refreshToken: 'a'.repeat(64) })).rejects.toBeInstanceOf(UnauthorisedException);
      expect(tokens.issueAccessToken).not.toHaveBeenCalled();
    });

    it('rejects when the user behind a live token no longer exists', async () => {
      tokens.consumeRefreshToken.mockResolvedValue(USER.id);
      users.findById.mockResolvedValue(null);

      await expect(auth.refresh({ refreshToken: 'a'.repeat(64) })).rejects.toBeInstanceOf(UnauthorisedException);
    });
  });

  describe('currentUser', () => {
    it('returns the user behind a verified token', async () => {
      users.findById.mockResolvedValue(USER);

      await expect(auth.currentUser(USER.id)).resolves.toBe(USER);
    });

    it('returns AUTH-401 rather than 404 for a token naming a deleted user', async () => {
      users.findById.mockResolvedValue(null);

      await expect(auth.currentUser(USER.id)).rejects.toBeInstanceOf(UnauthorisedException);
    });
  });
});

import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Test } from '@nestjs/testing';
import { decode, sign } from 'jsonwebtoken';
import { UnauthorisedException } from '../common/errors/auth.exceptions';
import { AuthConfig } from '../config/configuration';
import { Role } from '../users/role.enum';
import { AuthenticatedUser } from '../users/user.entity';
import { RefreshTokenRepository, RefreshTokenRow } from './refresh-token.repository';
import { REQUIRED_CLAIMS } from './token-claims';
import { TokenService } from './token.service';

const SECRET = 'test-secret-at-least-thirty-two-characters';

const USER: AuthenticatedUser = {
  id: '8f14e45f-ceea-4c1b-9d3b-1a2b3c4d5e6f',
  username: 'demo1',
  accountId: 1,
  roles: [Role.CUSTOMER],
};

/** A refresh-token repository held in memory, so the tests need no database. */
class FakeRefreshTokenRepository {
  rows = new Map<string, RefreshTokenRow & { token_hash: string }>();
  private sequence = 0;

  async create(userId: string, tokenHash: string, expiresOn: Date): Promise<void> {
    this.sequence += 1;
    this.rows.set(tokenHash, {
      id: `00000000-0000-4000-8000-${String(this.sequence).padStart(12, '0')}`,
      user_id: userId,
      token_hash: tokenHash,
      consumed_on: null,
      revoked_on: null,
      expires_on: expiresOn,
    });
  }

  async findByHash(tokenHash: string): Promise<RefreshTokenRow | null> {
    return this.rows.get(tokenHash) ?? null;
  }

  async consume(id: string): Promise<boolean> {
    for (const row of this.rows.values()) {
      if (row.id === id && row.consumed_on === null && row.revoked_on === null && row.expires_on > new Date()) {
        row.consumed_on = new Date();
        return true;
      }
    }
    return false;
  }

  async revokeAllForUser(userId: string): Promise<number> {
    let revoked = 0;
    for (const row of this.rows.values()) {
      if (row.user_id === userId && row.revoked_on === null && row.consumed_on === null) {
        row.revoked_on = new Date();
        revoked += 1;
      }
    }
    return revoked;
  }
}

describe('TokenService', () => {
  let tokens: TokenService;
  let refreshTokens: FakeRefreshTokenRepository;

  const jwtConfig: AuthConfig['jwt'] = {
    secret: SECRET,
    issuer: 'auth-service',
    accessTokenTtlSeconds: 900,
    refreshTokenTtlSeconds: 604800,
  };

  beforeEach(async () => {
    refreshTokens = new FakeRefreshTokenRepository();

    const moduleRef = await Test.createTestingModule({
      providers: [
        TokenService,
        JwtService,
        { provide: RefreshTokenRepository, useValue: refreshTokens },
        { provide: ConfigService, useValue: { get: () => jwtConfig } },
      ],
    }).compile();

    tokens = moduleRef.get(TokenService);
  });

  describe('access token issuance', () => {
    it('carries exactly the claims the contract fixes', async () => {
      const { token } = await tokens.issueAccessToken(USER);
      const claims = decode(token) as Record<string, unknown>;

      expect(Object.keys(claims).sort()).toEqual([...REQUIRED_CLAIMS].sort());
      expect(claims.sub).toBe(USER.id);
      expect(claims.accountId).toBe(1);
      expect(claims.roles).toEqual(['CUSTOMER']);
      expect(claims.iss).toBe('auth-service');
      expect(typeof claims.iat).toBe('number');
      expect(typeof claims.exp).toBe('number');
    });

    it('signs with HS256 and expires fifteen minutes after issue', async () => {
      const { token, expiresIn } = await tokens.issueAccessToken(USER);
      const decoded = decode(token, { complete: true });

      expect(decoded?.header.alg).toBe('HS256');
      expect(expiresIn).toBe(900);

      const claims = decoded?.payload as { iat: number; exp: number };
      expect(claims.exp - claims.iat).toBe(900);
    });

    it('does not put the username or anything private in the payload', async () => {
      const { token } = await tokens.issueAccessToken(USER);
      const claims = decode(token) as Record<string, unknown>;

      expect(claims).not.toHaveProperty('username');
      expect(claims).not.toHaveProperty('passwordHash');
    });
  });

  describe('access token verification', () => {
    it('accepts a token it issued', async () => {
      const { token } = await tokens.issueAccessToken(USER);
      const claims = await tokens.verifyAccessToken(token);

      expect(claims.sub).toBe(USER.id);
      expect(claims.accountId).toBe(1);
    });

    it('rejects a token signed with another secret', async () => {
      const forged = sign({ sub: USER.id, accountId: 1, roles: ['ADMIN'] }, 'a-different-secret-entirely', {
        algorithm: 'HS256',
        expiresIn: 900,
        issuer: 'auth-service',
      });

      await expect(tokens.verifyAccessToken(forged)).rejects.toBeInstanceOf(UnauthorisedException);
    });

    it('rejects an expired token', async () => {
      const expired = sign({ sub: USER.id, accountId: 1, roles: ['CUSTOMER'] }, SECRET, {
        algorithm: 'HS256',
        expiresIn: -60,
        issuer: 'auth-service',
      });

      await expect(tokens.verifyAccessToken(expired)).rejects.toBeInstanceOf(UnauthorisedException);
    });

    it('rejects a tampered payload', async () => {
      const { token } = await tokens.issueAccessToken(USER);
      const [header, , signature] = token.split('.');
      const tamperedPayload = Buffer.from(
        JSON.stringify({ sub: USER.id, accountId: 2, roles: ['ADMIN'], iat: 1, exp: 9999999999, iss: 'auth-service' }),
      ).toString('base64url');

      await expect(tokens.verifyAccessToken(`${header}.${tamperedPayload}.${signature}`)).rejects.toBeInstanceOf(
        UnauthorisedException,
      );
    });

    it('rejects an unsigned token that asks for the none algorithm', async () => {
      const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
      const payload = Buffer.from(
        JSON.stringify({ sub: USER.id, accountId: 1, roles: ['ADMIN'], iat: 1, exp: 9999999999, iss: 'auth-service' }),
      ).toString('base64url');

      await expect(tokens.verifyAccessToken(`${header}.${payload}.`)).rejects.toBeInstanceOf(UnauthorisedException);
    });

    it('rejects a token that is not a token', async () => {
      await expect(tokens.verifyAccessToken('not.a.jwt')).rejects.toBeInstanceOf(UnauthorisedException);
    });
  });

  describe('refresh token rotation', () => {
    it('issues an opaque token and stores only its hash', async () => {
      const token = await tokens.issueRefreshToken(USER.id);

      expect(token).toMatch(/^[0-9a-f]{64}$/);
      expect(refreshTokens.rows.has(token)).toBe(false);
      expect(refreshTokens.rows.size).toBe(1);
    });

    it('exchanges a live token for its user and consumes it', async () => {
      const token = await tokens.issueRefreshToken(USER.id);

      await expect(tokens.consumeRefreshToken(token)).resolves.toBe(USER.id);
      await expect(tokens.consumeRefreshToken(token)).rejects.toBeInstanceOf(UnauthorisedException);
    });

    it('revokes the whole chain when a consumed token is presented again', async () => {
      const first = await tokens.issueRefreshToken(USER.id);
      await tokens.consumeRefreshToken(first);
      const second = await tokens.issueRefreshToken(USER.id);

      await expect(tokens.consumeRefreshToken(first)).rejects.toBeInstanceOf(UnauthorisedException);

      // The replay took the live token with it, so the honest client is logged out too.
      await expect(tokens.consumeRefreshToken(second)).rejects.toBeInstanceOf(UnauthorisedException);
    });

    it('rejects a token it never issued', async () => {
      await expect(tokens.consumeRefreshToken('f'.repeat(64))).rejects.toBeInstanceOf(UnauthorisedException);
    });

    it('rejects an expired refresh token', async () => {
      const token = await tokens.issueRefreshToken(USER.id);
      for (const row of refreshTokens.rows.values()) {
        row.expires_on = new Date(Date.now() - 1000);
      }

      await expect(tokens.consumeRefreshToken(token)).rejects.toBeInstanceOf(UnauthorisedException);
    });
  });
});

/**
 * Contract parity between the Sprint 6 stub and the Sprint 8 service.
 *
 * The Sprint 8 acceptance criterion is that swapping the stub for the real
 * service is a configuration change: no code change in the Trade REST API, no
 * code change in the Angular UI. That holds only if a token from either one
 * verifies against the other's secret and carries the same claims, with the same
 * names and the same types.
 *
 * This test is the proof. It signs with both implementations and cross-verifies.
 * It fails the moment somebody adds a claim to one side, renames one, changes an
 * algorithm, or lets the two disagree about a demo user's identifier.
 *
 * Run it with `npm run test:parity` from `services/auth-service`.
 */

import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { decode } from 'jsonwebtoken';
import { AuthConfig } from '../src/config/configuration';
import { RefreshTokenRepository } from '../src/tokens/refresh-token.repository';
import { REQUIRED_CLAIMS } from '../src/tokens/token-claims';
import { TokenService } from '../src/tokens/token.service';
import { DEMO_PASSWORD, DEMO_USERS } from '../src/users/demo-users';
import { Role } from '../src/users/role.enum';

/** Both sides sign with this. In development it is the value in both .env.example files. */
const SHARED_SECRET = 'development-only-shared-secret-change-me';

// The stub reads JWT_SECRET at load time, so it is set before the require below.
process.env.JWT_SECRET = SHARED_SECRET;

// eslint-disable-next-line @typescript-eslint/no-var-requires
const stub = require('../../auth-stub/src/server.js') as {
  issueAccessToken: (user: { id: string; accountId: number; roles: string[] }, now?: number) => {
    token: string;
    expiresIn: number;
  };
  verifyAccessToken: (token: string) => Record<string, unknown> | null;
  demoUserId: (username: string) => string;
  DEMO_USERS: Array<{ id: string; username: string; accountId: number; roles: string[] }>;
  DEMO_PASSWORD: string;
  ACCESS_TOKEN_TTL_SECONDS: number;
  ISSUER: string;
};

const jwtConfig: AuthConfig['jwt'] = {
  secret: SHARED_SECRET,
  issuer: 'auth-service',
  accessTokenTtlSeconds: 900,
  refreshTokenTtlSeconds: 604800,
};

const service = new TokenService(
  new JwtService(),
  {} as RefreshTokenRepository,
  { get: () => jwtConfig } as unknown as ConfigService<AuthConfig, true>,
);

const DEMO_1 = DEMO_USERS[0];

describe('stub and service token parity', () => {
  describe('the demo users', () => {
    it('agree on username, account and roles', () => {
      expect(stub.DEMO_USERS.map((user) => user.username)).toEqual(DEMO_USERS.map((user) => user.username));
      expect(stub.DEMO_USERS.map((user) => user.accountId)).toEqual([1, 2, 3, 4, 5]);
      expect(DEMO_USERS.map((user) => user.accountId)).toEqual([1, 2, 3, 4, 5]);
      expect(stub.DEMO_USERS.every((user) => user.roles.length === 1 && user.roles[0] === Role.CUSTOMER)).toBe(true);
    });

    it('derive the same sub for the same username', () => {
      for (const user of DEMO_USERS) {
        expect(stub.demoUserId(user.username)).toBe(user.id);
      }
    });

    it('share one password', () => {
      expect(stub.DEMO_PASSWORD).toBe(DEMO_PASSWORD);
    });
  });

  describe('a token issued by the stub', () => {
    it('verifies in the service, which is what makes the cutover a configuration change', async () => {
      const { token } = stub.issueAccessToken({ id: DEMO_1.id, accountId: DEMO_1.accountId, roles: [Role.CUSTOMER] });

      const claims = await service.verifyAccessToken(token);

      expect(claims.sub).toBe(DEMO_1.id);
      expect(claims.accountId).toBe(1);
      expect(claims.roles).toEqual(['CUSTOMER']);
      expect(claims.iss).toBe('auth-stub');
    });
  });

  describe('a token issued by the service', () => {
    it('verifies in the stub', async () => {
      const { token } = await service.issueAccessToken({
        id: DEMO_1.id,
        username: DEMO_1.username,
        accountId: DEMO_1.accountId,
        roles: [Role.CUSTOMER],
      });

      const claims = stub.verifyAccessToken(token);

      expect(claims).not.toBeNull();
      expect(claims?.sub).toBe(DEMO_1.id);
      expect(claims?.accountId).toBe(1);
      expect(claims?.iss).toBe('auth-service');
    });
  });

  describe('the claim sets', () => {
    it('carry exactly the same claim names, and only the contract claims', async () => {
      const fromStub = stub.issueAccessToken({ id: DEMO_1.id, accountId: DEMO_1.accountId, roles: [Role.CUSTOMER] });
      const fromService = await service.issueAccessToken({
        id: DEMO_1.id,
        username: DEMO_1.username,
        accountId: DEMO_1.accountId,
        roles: [Role.CUSTOMER],
      });

      const stubClaims = decode(fromStub.token) as Record<string, unknown>;
      const serviceClaims = decode(fromService.token) as Record<string, unknown>;
      const contractClaims = [...REQUIRED_CLAIMS].sort();

      expect(Object.keys(stubClaims).sort()).toEqual(contractClaims);
      expect(Object.keys(serviceClaims).sort()).toEqual(contractClaims);
    });

    it('carry the same type for every claim', async () => {
      const fromStub = decode(
        stub.issueAccessToken({ id: DEMO_1.id, accountId: DEMO_1.accountId, roles: [Role.CUSTOMER] }).token,
      ) as Record<string, unknown>;
      const fromService = decode(
        (
          await service.issueAccessToken({
            id: DEMO_1.id,
            username: DEMO_1.username,
            accountId: DEMO_1.accountId,
            roles: [Role.CUSTOMER],
          })
        ).token,
      ) as Record<string, unknown>;

      for (const claim of REQUIRED_CLAIMS) {
        expect(typeof fromService[claim]).toBe(typeof fromStub[claim]);
      }
      expect(Array.isArray(fromStub.roles)).toBe(true);
      expect(Array.isArray(fromService.roles)).toBe(true);
    });

    it('agree on the algorithm and the fifteen-minute lifetime', async () => {
      const fromStub = decode(
        stub.issueAccessToken({ id: DEMO_1.id, accountId: DEMO_1.accountId, roles: [Role.CUSTOMER] }).token,
        { complete: true },
      );
      const fromService = decode(
        (
          await service.issueAccessToken({
            id: DEMO_1.id,
            username: DEMO_1.username,
            accountId: DEMO_1.accountId,
            roles: [Role.CUSTOMER],
          })
        ).token,
        { complete: true },
      );

      expect(fromStub?.header.alg).toBe('HS256');
      expect(fromService?.header.alg).toBe('HS256');
      expect(stub.ACCESS_TOKEN_TTL_SECONDS).toBe(jwtConfig.accessTokenTtlSeconds);

      const stubPayload = fromStub?.payload as { iat: number; exp: number };
      const servicePayload = fromService?.payload as { iat: number; exp: number };
      expect(stubPayload.exp - stubPayload.iat).toBe(900);
      expect(servicePayload.exp - servicePayload.iat).toBe(900);
    });

    it('only differ in the issuer, which is how a cutover is traced', () => {
      expect(stub.ISSUER).toBe('auth-stub');
      expect(jwtConfig.issuer).toBe('auth-service');
    });
  });

  describe('a token signed with a different secret', () => {
    it('is rejected by both, so the shared secret is doing the work', async () => {
      const other = new TokenService(
        new JwtService(),
        {} as RefreshTokenRepository,
        {
          get: () => ({ ...jwtConfig, secret: 'a-completely-different-secret-value' }),
        } as unknown as ConfigService<AuthConfig, true>,
      );

      const { token } = await other.issueAccessToken({
        id: DEMO_1.id,
        username: DEMO_1.username,
        accountId: DEMO_1.accountId,
        roles: [Role.CUSTOMER],
      });

      expect(stub.verifyAccessToken(token)).toBeNull();
      await expect(service.verifyAccessToken(token)).rejects.toThrow();
    });
  });
});

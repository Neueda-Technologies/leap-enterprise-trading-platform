import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { createHash, randomBytes } from 'node:crypto';
import { UnauthorisedException } from '../common/errors/auth.exceptions';
import { AuthConfig } from '../config/configuration';
import { AuthenticatedUser } from '../users/user.entity';
import { RefreshTokenRepository } from './refresh-token.repository';
import { AccessTokenClaims } from './token-claims';

/**
 * Issues and verifies tokens. The only place in the service that holds the
 * signing secret.
 *
 * Two token types, for two different jobs:
 *
 * | Token   | Form              | Lifetime | Revocable | Why |
 * |---|---|---|---|---|
 * | Access  | Signed JWT        | 15 min   | No        | Verified by the Trade REST API without a call back here. Nothing can withdraw it, so it expires quickly. |
 * | Refresh | Opaque random hex | 7 days   | Yes       | Only this service ever reads it. Stored hashed, single use, and revocable the moment theft is suspected. |
 *
 * Making the access token stateless is what lets every other service verify a
 * request with a signature check and no network hop. The cost is that it cannot
 * be withdrawn, and fifteen minutes is the size of that cost.
 */
@Injectable()
export class TokenService {
  private readonly logger = new Logger(TokenService.name);

  constructor(
    private readonly jwt: JwtService,
    private readonly refreshTokens: RefreshTokenRepository,
    private readonly config: ConfigService<AuthConfig, true>,
  ) {}

  private get settings() {
    return this.config.get('jwt', { infer: true });
  }

  /**
   * Signs an access token carrying exactly the contract claims.
   *
   * `iat` and `exp` are added by the signer from `expiresIn`, and `iss` from
   * `issuer`. Do not set them by hand: a hand-rolled `exp` computed from a clock
   * read a few lines earlier is how tokens end up one second short.
   */
  async issueAccessToken(user: AuthenticatedUser): Promise<{ token: string; expiresIn: number }> {
    const { secret, issuer, accessTokenTtlSeconds } = this.settings;

    const token = await this.jwt.signAsync(
      {
        sub: user.id,
        accountId: user.accountId,
        roles: user.roles,
      },
      {
        secret,
        issuer,
        algorithm: 'HS256',
        expiresIn: accessTokenTtlSeconds,
      },
    );

    return { token, expiresIn: accessTokenTtlSeconds };
  }

  /**
   * Verifies a token and returns its claims.
   *
   * `algorithms` is pinned. Without it, a verifier accepts whatever the token's
   * own header asks for, and an attacker re-signs a payload with `alg: none` or
   * with HMAC over a public key. The issuer is read but not required, because
   * the contract says a consumer must accept both `auth-service` and
   * `auth-stub` during the Sprint 8 cutover.
   */
  async verifyAccessToken(token: string): Promise<AccessTokenClaims> {
    try {
      return await this.jwt.verifyAsync<AccessTokenClaims>(token, {
        secret: this.settings.secret,
        algorithms: ['HS256'],
      });
    } catch (error) {
      this.logger.warn('token rejected', {
        event: 'token.rejected',
        reason: error instanceof Error ? error.name : 'unknown',
      });
      throw new UnauthorisedException();
    }
  }

  /** 256 bits of randomness, stored as its SHA-256 and handed to the client in the clear. */
  async issueRefreshToken(userId: string): Promise<string> {
    const token = randomBytes(32).toString('hex');
    const expiresOn = new Date(Date.now() + this.settings.refreshTokenTtlSeconds * 1000);
    await this.refreshTokens.create(userId, this.hash(token), expiresOn);
    return token;
  }

  /**
   * Exchanges a refresh token for the identity behind it, and burns it.
   *
   * Every failure path returns the same AUTH-401. The replay path additionally
   * revokes the user's whole chain: a token presented for a second time means
   * either the client repeated a request or somebody stole the token, and the
   * service cannot tell the difference, so it assumes the worse of the two.
   */
  async consumeRefreshToken(presented: string): Promise<string> {
    const stored = await this.refreshTokens.findByHash(this.hash(presented));

    if (!stored) {
      throw new UnauthorisedException();
    }

    if (stored.consumed_on !== null) {
      const revoked = await this.refreshTokens.revokeAllForUser(stored.user_id);
      this.logger.warn('refresh token replayed', {
        event: 'refresh.replay',
        userId: stored.user_id,
        revoked,
      });
      throw new UnauthorisedException();
    }

    const consumed = await this.refreshTokens.consume(stored.id);
    if (!consumed) {
      // Revoked, expired, or lost a race with a concurrent refresh.
      throw new UnauthorisedException();
    }

    return stored.user_id;
  }

  /** Ends every live session for a user. Used by the replay response and by logout. */
  async revokeAllForUser(userId: string): Promise<number> {
    return this.refreshTokens.revokeAllForUser(userId);
  }

  private hash(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }
}

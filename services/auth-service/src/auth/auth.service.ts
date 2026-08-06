import { Injectable, Logger } from '@nestjs/common';
import { UnauthorisedException } from '../common/errors/auth.exceptions';
import { TokenPair } from '../tokens/token-claims';
import { TokenService } from '../tokens/token.service';
import { RegisterDto } from '../users/dto/register.dto';
import { UserRecord } from '../users/user.entity';
import { UsersService } from '../users/users.service';
import { LoginDto } from './dto/login.dto';
import { RefreshDto } from './dto/refresh.dto';

/**
 * The four flows the contract describes, and nothing else.
 *
 * The controller maps HTTP to these calls; this class decides what
 * authentication means. Splitting them that way is what lets the same flows be
 * driven from a test without an HTTP server, which is most of the Jest suite.
 */
@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly users: UsersService,
    private readonly tokens: TokenService,
  ) {}

  async register(dto: RegisterDto): Promise<UserRecord> {
    return this.users.register(dto);
  }

  /**
   * Verifies credentials and issues a token pair.
   *
   * Registration does not do this. The contract keeps them apart so that the
   * only route that can mint a session is one that has already checked a
   * password.
   */
  async login(dto: LoginDto): Promise<TokenPair> {
    const user = await this.users.validateCredentials(dto.username, dto.password);

    if (!user) {
      // One log line, one exception, for both an unknown username and a wrong
      // password. The username is logged because an operator investigating a
      // credential-stuffing run needs it. The password is not, ever.
      this.logger.warn('login failed', { event: 'login.failed', username: dto.username });
      throw new UnauthorisedException();
    }

    const pair = await this.issuePair(user);
    this.logger.log('login succeeded', {
      event: 'login.succeeded',
      userId: user.id,
      accountId: user.accountId,
    });
    return pair;
  }

  /**
   * Rotates a refresh token.
   *
   * The presented token is consumed before the new pair is issued, so a failure
   * halfway through leaves the old token dead rather than leaving two live
   * tokens for one session.
   */
  async refresh(dto: RefreshDto): Promise<TokenPair> {
    const userId = await this.tokens.consumeRefreshToken(dto.refreshToken);
    const user = await this.users.findById(userId);

    if (!user) {
      // The user was removed while a refresh token was still live.
      throw new UnauthorisedException();
    }

    this.logger.log('token refreshed', { event: 'refresh.succeeded', userId: user.id });
    return this.issuePair(user);
  }

  /** Resolves the identity behind a verified access token. */
  async currentUser(userId: string): Promise<UserRecord> {
    const user = await this.users.findById(userId);

    if (!user) {
      throw new UnauthorisedException();
    }

    return user;
  }

  private async issuePair(user: UserRecord): Promise<TokenPair> {
    const { token, expiresIn } = await this.tokens.issueAccessToken({
      id: user.id,
      username: user.username,
      accountId: user.accountId,
      roles: user.roles,
    });
    const refreshToken = await this.tokens.issueRefreshToken(user.id);

    return { accessToken: token, refreshToken, tokenType: 'Bearer', expiresIn };
  }
}

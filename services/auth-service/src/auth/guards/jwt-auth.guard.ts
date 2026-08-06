import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { Request } from 'express';
import { UnauthorisedException } from '../../common/errors/auth.exceptions';
import { AccessTokenClaims } from '../../tokens/token-claims';
import { TokenService } from '../../tokens/token.service';
import { AuthenticatedUser } from '../../users/user.entity';

/** The request, once the guard has attached the verified identity. */
export interface AuthenticatedRequest extends Request {
  user?: AuthenticatedUser;
  claims?: AccessTokenClaims;
}

/**
 * Verifies the bearer token and attaches the identity to the request.
 *
 * The order of the checks matters. The header is parsed, then the signature is
 * verified, and only then is anything read out of the payload. Reading a claim
 * from a decoded but unverified token is the most common JWT defect there is:
 * the payload is client-supplied data until the signature says otherwise.
 *
 * The guard is written by hand rather than taken from Passport so that the whole
 * mechanism is three visible steps. Passport's JWT strategy does the same work
 * behind two lines of configuration, which is fine in production code and
 * useless in a sprint whose learning outcome is how a guard works.
 */
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly tokens: TokenService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const token = this.extractBearerToken(request.headers.authorization);

    if (!token) {
      throw new UnauthorisedException();
    }

    // Throws UnauthorisedException on a bad signature, a wrong algorithm, an
    // expired token or a malformed one. Every case is the same 401 to the client.
    const claims = await this.tokens.verifyAccessToken(token);

    if (!claims.sub || typeof claims.accountId !== 'number' || !Array.isArray(claims.roles) || claims.roles.length === 0) {
      // A correctly signed token that does not carry the claims contract. It
      // will not have come from this service, so it is not trusted here.
      throw new UnauthorisedException();
    }

    request.claims = claims;
    request.user = {
      id: claims.sub,
      username: '',
      accountId: claims.accountId,
      roles: claims.roles,
    };

    return true;
  }

  /**
   * Pulls the token out of `Authorization: Bearer <token>`.
   *
   * The scheme comparison is case-insensitive, which RFC 7235 requires, and the
   * header must have exactly two parts. Accepting a bare token without the
   * scheme is a small convenience that makes the service accept things no
   * standards-compliant client sends.
   */
  private extractBearerToken(header: string | undefined): string | null {
    if (!header) {
      return null;
    }
    const [scheme, value, ...rest] = header.split(' ');
    if (rest.length > 0 || scheme?.toLowerCase() !== 'bearer' || !value) {
      return null;
    }
    return value;
  }
}

import { ExecutionContext } from '@nestjs/common';
import { UnauthorisedException } from '../../common/errors/auth.exceptions';
import { AccessTokenClaims } from '../../tokens/token-claims';
import { TokenService } from '../../tokens/token.service';
import { Role } from '../../users/role.enum';
import { AuthenticatedRequest, JwtAuthGuard } from './jwt-auth.guard';

const VALID_CLAIMS: AccessTokenClaims = {
  sub: '8f14e45f-ceea-4c1b-9d3b-1a2b3c4d5e6f',
  accountId: 3,
  roles: [Role.CUSTOMER],
  iat: 1790000000,
  exp: 1790000900,
  iss: 'auth-service',
};

/** Builds the smallest ExecutionContext the guard actually reads. */
function contextWith(authorization?: string): { context: ExecutionContext; request: AuthenticatedRequest } {
  const request = { headers: authorization ? { authorization } : {} } as AuthenticatedRequest;
  const context = {
    switchToHttp: () => ({ getRequest: () => request }),
  } as unknown as ExecutionContext;
  return { context, request };
}

describe('JwtAuthGuard', () => {
  let verifyAccessToken: jest.Mock;
  let guard: JwtAuthGuard;

  beforeEach(() => {
    verifyAccessToken = jest.fn();
    guard = new JwtAuthGuard({ verifyAccessToken } as unknown as TokenService);
  });

  it('attaches the verified identity and allows the request', async () => {
    verifyAccessToken.mockResolvedValue(VALID_CLAIMS);
    const { context, request } = contextWith('Bearer a.valid.token');

    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(verifyAccessToken).toHaveBeenCalledWith('a.valid.token');
    expect(request.user).toEqual({ id: VALID_CLAIMS.sub, username: '', accountId: 3, roles: [Role.CUSTOMER] });
    expect(request.claims).toEqual(VALID_CLAIMS);
  });

  it('accepts the scheme in any case, as RFC 7235 requires', async () => {
    verifyAccessToken.mockResolvedValue(VALID_CLAIMS);
    const { context } = contextWith('bearer a.valid.token');

    await expect(guard.canActivate(context)).resolves.toBe(true);
  });

  it.each([
    ['no Authorization header', undefined],
    ['an empty header', ''],
    ['the wrong scheme', 'Basic ZGVtbzE6cGFzcw=='],
    ['a bare token with no scheme', 'a.valid.token'],
    ['a header with too many parts', 'Bearer a.valid.token extra'],
    ['a scheme with no token', 'Bearer'],
  ])('rejects %s without calling the verifier', async (_case, header) => {
    const { context } = contextWith(header);

    await expect(guard.canActivate(context)).rejects.toBeInstanceOf(UnauthorisedException);
    expect(verifyAccessToken).not.toHaveBeenCalled();
  });

  it('rejects a token the verifier refuses, for example a wrong signature or an expiry', async () => {
    verifyAccessToken.mockRejectedValue(new UnauthorisedException());
    const { context, request } = contextWith('Bearer forged.or.expired');

    await expect(guard.canActivate(context)).rejects.toBeInstanceOf(UnauthorisedException);
    expect(request.user).toBeUndefined();
  });

  it.each([
    ['no sub', { ...VALID_CLAIMS, sub: '' }],
    ['a string accountId', { ...VALID_CLAIMS, accountId: '3' }],
    ['no roles array', { ...VALID_CLAIMS, roles: 'CUSTOMER' }],
    ['an empty roles array', { ...VALID_CLAIMS, roles: [] }],
  ])('rejects a correctly signed token with %s', async (_case, claims) => {
    verifyAccessToken.mockResolvedValue(claims);
    const { context, request } = contextWith('Bearer signed.but.wrong');

    await expect(guard.canActivate(context)).rejects.toBeInstanceOf(UnauthorisedException);
    expect(request.user).toBeUndefined();
  });
});

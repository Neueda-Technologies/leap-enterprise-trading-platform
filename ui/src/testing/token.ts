import { AccessTokenClaims } from '../app/core/models/auth-api';

/**
 * Build an access token for a test.
 *
 * The signature is a fixed string, because nothing in the browser verifies it. If a test ever
 * needs a genuinely signed token, the Auth service is the thing that signs tokens.
 */
export function makeAccessToken(claims: Partial<AccessTokenClaims> = {}): string {
  const issuedAt = Math.floor(Date.now() / 1000);
  const payload: AccessTokenClaims = {
    sub: '8f14e45f-ceea-4c1b-9d3b-1a2b3c4d5e6f',
    accountId: 1,
    roles: ['CUSTOMER'],
    iat: issuedAt,
    exp: issuedAt + 900,
    iss: 'auth-service',
    ...claims,
  };

  return `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode(payload)}.test-signature`;
}

/** A token whose `exp` has already passed. */
export function makeExpiredAccessToken(): string {
  const issuedAt = Math.floor(Date.now() / 1000) - 3600;
  return makeAccessToken({ iat: issuedAt, exp: issuedAt + 900 });
}

function encode(value: unknown): string {
  return btoa(JSON.stringify(value)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

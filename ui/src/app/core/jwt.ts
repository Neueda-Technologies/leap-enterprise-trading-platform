import { AccessTokenClaims } from './models/auth-api';

/**
 * Read the claims out of an access token without verifying it.
 *
 * The browser cannot verify an HS256 signature, because verifying it would mean holding the
 * signing secret, and anything the browser holds the user holds. So this decode tells the UI
 * two things only: which account to address, and whether the token has already expired so
 * that the app can refresh before making a doomed request. Every authorisation decision is
 * taken by the Trade REST API, which does verify the signature.
 *
 * Returns null for anything that is not a well-formed JWT payload.
 */
export function decodeAccessToken(token: string | null | undefined): AccessTokenClaims | null {
  if (!token) {
    return null;
  }

  const payload = token.split('.')[1];
  if (!payload) {
    return null;
  }

  try {
    return JSON.parse(decodeBase64Url(payload)) as AccessTokenClaims;
  } catch {
    return null;
  }
}

/**
 * True when the token carries an `exp` claim that has already passed.
 *
 * `skewSeconds` treats a token that is about to expire as expired, so that the app refreshes
 * rather than sending a request that will land at the API a moment after the deadline.
 */
export function isExpired(claims: AccessTokenClaims | null, skewSeconds = 5): boolean {
  if (!claims || typeof claims.exp !== 'number') {
    return true;
  }
  const nowSeconds = Math.floor(Date.now() / 1000);
  return claims.exp <= nowSeconds + skewSeconds;
}

/** base64url is base64 with two characters swapped and the padding dropped. */
function decodeBase64Url(value: string): string {
  const base64 = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), '=');
  const binary = atob(padded);
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

import { Role } from '../users/role.enum';

/**
 * The access token payload, exactly as `contracts/auth-api.yaml` defines it.
 *
 * This interface is normative. The Trade REST API reads `accountId` from the
 * verified token and compares it against the account in the request, so an extra
 * claim is harmless but a renamed or missing one breaks authorisation across the
 * platform.
 *
 * Nothing sensitive goes in here. A JWT payload is base64, not encryption, and
 * anyone holding the token can read every claim.
 */
export interface AccessTokenClaims {
  /** The user identifier, a UUID. Stable for the life of the user. */
  sub: string;
  /** The numeric trading account key, `ACCOUNTS.id`. */
  accountId: number;
  /** Authorisation roles. Always present, never empty. */
  roles: Role[];
  /** Issued at, seconds since the Unix epoch. */
  iat: number;
  /** Expiry, seconds since the Unix epoch. Fifteen minutes after `iat`. */
  exp: number;
  /** `auth-service` here, `auth-stub` from the Sprint 6 stub. Consumers must not require a value. */
  iss: string;
}

/** The claim names the contract fixes. Used by the parity test and by the token tests. */
export const REQUIRED_CLAIMS = ['sub', 'accountId', 'roles', 'iat', 'exp', 'iss'] as const;

/** What `/auth/login` and `/auth/refresh` return. */
export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  tokenType: 'Bearer';
  expiresIn: number;
}

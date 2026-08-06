/*
 * Typed models for the Auth service, hand-written from `docs/contracts/auth-api.yaml`.
 *
 * The provided Node auth stub and the Sprint 8 NestJS service implement the same contract,
 * so this file describes both. Nothing here may depend on which one is running.
 */

export type Role = 'CUSTOMER' | 'ADMIN';

/** The error catalogue served by the Auth service. */
export type AuthErrorCode = 'AUTH-401' | 'AUTH-409' | 'VAL-422';

export interface LoginRequest {
  username: string;
  password: string;
}

export interface RefreshRequest {
  refreshToken: string;
}

export interface RegisterRequest {
  username: string;
  password: string;
  /** The numeric trading account key, `ACCOUNTS.id`, that this user will trade. */
  accountId: number;
}

export interface TokenResponse {
  /** Signed JWT carrying the claims in `AccessTokenClaims`. */
  accessToken: string;
  /** Opaque, stored server-side, revocable, rotated on every use. */
  refreshToken: string;
  tokenType: 'Bearer';
  /** Access token lifetime in seconds. Fifteen minutes under the contract. */
  expiresIn: number;
}

export interface UserResponse {
  /** The value carried in the `sub` claim. */
  id: string;
  username: string;
  /** The numeric trading account key, `ACCOUNTS.id`. */
  accountId: number;
  roles: Role[];
  createdOn?: string;
}

/**
 * The normative claims contract. The UI decodes these to know when the access token has
 * expired and which account to address.
 *
 * A JWT payload is base64, not encrypted, and the browser does not verify the signature.
 * Treat anything read from here as a hint for the user interface only. Authorisation is
 * decided by the Trade REST API, which does verify the signature.
 */
export interface AccessTokenClaims {
  /** The user identifier, a UUID. Stable for the life of the user. */
  sub: string;
  /** The numeric trading account key, `ACCOUNTS.id`. */
  accountId: number;
  roles: Role[];
  /** Issued-at, seconds since the Unix epoch. */
  iat: number;
  /** Expiry, seconds since the Unix epoch. */
  exp: number;
  /** `auth-stub` for the provided stub, `auth-service` for the Sprint 8 service. */
  iss?: string;
}

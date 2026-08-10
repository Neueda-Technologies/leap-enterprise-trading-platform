/**
 * =============================================================================
 * Auth stub: a fake login service for Sprints 6 and 7
 * =============================================================================
 *
 * WHY THIS FILE EXISTS
 *
 * Sprint 6 builds the Trade REST API, and every route on it has to verify a JWT.
 * Verifying a token needs something to issue one. Node and NestJS are not taught
 * until Sprint 8, so this stub is provided rather than built: it issues tokens
 * with exactly the claims the real service will issue, signed with the same
 * algorithm and the same secret, so that Spring Boot's verification code is
 * written once and does not change when the real service arrives.
 *
 * It is a fixture, not a deliverable. There is nothing to implement here, no
 * tests to write against it, and no marks attached to it. Read it, use it, and
 * delete it in Sprint 8.
 *
 * WHAT IT IS NOT
 *
 * There is no database, no registration, no password hashing and no refresh
 * token store. Five users are hard-coded with one shared password. Anything
 * resembling this in a real service is a critical finding.
 *
 * WHAT TO READ IT FOR
 *
 * Three things worth understanding before Sprint 8:
 *
 *   1. A JWT is three base64url segments joined by dots: header, payload,
 *      signature. The payload is encoded, not encrypted. Paste a token into
 *      jwt.io and every claim is readable.
 *   2. The signature is what makes the token trustworthy. It is an HMAC of the
 *      first two segments using a shared secret. Change one byte of the payload
 *      and the signature no longer matches.
 *   3. Verification means checking the signature, the expiry, and the algorithm
 *      the token asks for. A verifier that decodes the payload without checking
 *      the signature is trusting whatever the client sent.
 *
 * RUNNING IT
 *
 *   JWT_SECRET=development-only-shared-secret-change-me node src/server.js
 *
 * The port defaults to 3001, so the stub and the Sprint 8 service can run side
 * by side during the cutover. Set PORT=3000 (as the Docker Compose file does) to
 * put it where the contract says the auth service lives.
 * =============================================================================
 */

'use strict';

const http = require('node:http');
const { createHash, createHmac, timingSafeEqual } = require('node:crypto');

// -----------------------------------------------------------------------------
// Configuration
//
// The secret is read from the environment, not written in this file. It has to
// match the secret the Trade REST API verifies with, and, in Sprint 8, the one
// the NestJS service signs with. A secret in source control is a finding even
// when the source is a training repository.
// -----------------------------------------------------------------------------
const PORT = Number.parseInt(process.env.PORT || '3001', 10);
const JWT_SECRET = process.env.JWT_SECRET;

// `auth-stub`, not `auth-service`. During the Sprint 8 cutover this claim is how
// a team proves which implementation signed a token they are holding.
const ISSUER = process.env.JWT_ISSUER || 'auth-stub';

// Fifteen minutes, the same lifetime the real service uses. Short, because an
// access token cannot be withdrawn once it is issued.
const ACCESS_TOKEN_TTL_SECONDS = Number.parseInt(process.env.ACCESS_TOKEN_TTL_SECONDS || '900', 10);

if (!JWT_SECRET) {
  process.stderr.write('JWT_SECRET is not set. The stub cannot sign tokens without it.\n');
  process.exit(1);
}

// -----------------------------------------------------------------------------
// The five demo users
//
// Each maps to one of the seeded trading accounts, ACCOUNTS.id 1 to 5, so
// logging in as demo3 gives a token that can trade account 3. The Sprint 8
// service seeds the same five with the same identifiers.
//
// The password is shared and committed. That is acceptable here and nowhere
// else: this service is deleted before anything real depends on it.
// -----------------------------------------------------------------------------
const DEMO_PASSWORD = 'Trainee#2026';

/**
 * Namespace for deriving each demo user's `sub` claim.
 *
 * The stub has no database, so it cannot look up a user identifier. It computes
 * one instead, with a name-based UUID (RFC 4122 version 5). The Sprint 8 service
 * runs the identical computation when it seeds its demo users, so `demo1` has
 * the same `sub` in both implementations and a token from either names the same
 * person. The duplicated function below is deliberate: this file must have no
 * dependency on the service that replaces it.
 */
const DEMO_USER_NAMESPACE = 'a1e3c9f2-5b7d-4c8e-9f10-2b6d4e8a7c31';

function demoUserId(username) {
  const namespaceBytes = Buffer.from(DEMO_USER_NAMESPACE.replace(/-/g, ''), 'hex');
  const digest = createHash('sha1').update(namespaceBytes).update(Buffer.from(username, 'utf8')).digest();

  const bytes = Buffer.from(digest.subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50; // version 5
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant

  const hex = bytes.toString('hex');
  return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join('-');
}

const DEMO_USERS = [1, 2, 3, 4, 5].map((accountId) => ({
  id: demoUserId(`demo${accountId}`),
  username: `demo${accountId}`,
  accountId,
  roles: ['CUSTOMER'],
}));

// -----------------------------------------------------------------------------
// The error envelope
//
// Identical to the Trade REST API's, so the Angular UI has one error handler for
// the whole platform. Two codes are used here: AUTH-401 for any authentication
// failure and VAL-422 for a body that does not parse or is missing a field.
//
// Every failure returns the same message. "Unknown user" and "wrong password"
// are two different answers, and telling them apart lets an attacker confirm
// which usernames exist before trying a single password.
// -----------------------------------------------------------------------------
const ERRORS = {
  unauthorised: { status: 401, body: { errorCode: 'AUTH-401', message: 'Unauthorised' } },
  invalidInput: { status: 422, body: { errorCode: 'VAL-422', message: 'Invalid input' } },
  notFound: { status: 404, body: { errorCode: 'AUTH-401', message: 'Unauthorised' } },
};

// -----------------------------------------------------------------------------
// JWT signing, by hand
//
// The real service uses a library. This does it in twenty lines so that the
// three parts of a token are visible.
// -----------------------------------------------------------------------------

/** base64url is base64 with two characters swapped and the padding removed. */
function base64url(input) {
  return Buffer.from(input).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/**
 * Signs a set of claims with HS256.
 *
 * HS256 means HMAC-SHA256: one secret, held by both the signer and the verifier.
 * That is why the stub and the Trade REST API must be given the same
 * JWT_SECRET. The alternative, RS256, signs with a private key and verifies with
 * a public one, so a verifier cannot forge tokens. The contract documents that
 * as an upgrade, not a requirement.
 */
function signJwt(claims) {
  const header = { alg: 'HS256', typ: 'JWT' };
  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;
  const signature = createHmac('sha256', JWT_SECRET).update(signingInput).digest('base64url');
  return `${signingInput}.${signature}`;
}

/**
 * Builds the claim set the contract fixes, and nothing else.
 *
 * | Claim       | Meaning |
 * |---|---|
 * | `sub`       | The user identifier, a UUID. Not the username: usernames change. |
 * | `accountId` | The numeric trading account key, ACCOUNTS.id. The Trade REST API compares it against the account in the request. |
 * | `roles`     | Authorisation roles. Never empty. |
 * | `iat`       | Issued at, seconds since the Unix epoch. |
 * | `exp`       | Expiry, seconds since the Unix epoch. |
 * | `iss`       | `auth-stub` here, `auth-service` in Sprint 8. |
 *
 * Seconds, not milliseconds. `Date.now()` returns milliseconds and a token whose
 * `exp` is a millisecond value expires in the year 58000, which is a defect a
 * reviewer will find.
 */
function issueAccessToken(user, now = Math.floor(Date.now() / 1000)) {
  return {
    token: signJwt({
      sub: user.id,
      accountId: user.accountId,
      roles: user.roles,
      iat: now,
      exp: now + ACCESS_TOKEN_TTL_SECONDS,
      iss: ISSUER,
    }),
    expiresIn: ACCESS_TOKEN_TTL_SECONDS,
  };
}

/**
 * Verifies a token: signature first, then expiry, then the claims.
 *
 * The order is the point. Anything read out of the payload before the signature
 * check is client-supplied data. The algorithm from the token's own header is
 * never trusted either: a verifier that honours `alg: none` accepts unsigned
 * tokens, which is the oldest JWT vulnerability there is.
 *
 * Returns the claims, or null. The caller turns null into AUTH-401.
 */
function verifyAccessToken(token) {
  const parts = String(token).split('.');
  if (parts.length !== 3) {
    return null;
  }

  const [encodedHeader, encodedPayload, signature] = parts;

  let header;
  try {
    header = JSON.parse(Buffer.from(encodedHeader, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  if (header.alg !== 'HS256') {
    return null;
  }

  const expected = createHmac('sha256', JWT_SECRET).update(`${encodedHeader}.${encodedPayload}`).digest('base64url');
  const given = Buffer.from(signature);
  const wanted = Buffer.from(expected);

  // Length-checked, then compared in constant time. A plain === leaks how many
  // leading bytes were correct through its timing, which is enough to forge a
  // signature one byte at a time.
  if (given.length !== wanted.length || !timingSafeEqual(given, wanted)) {
    return null;
  }

  let claims;
  try {
    claims = JSON.parse(Buffer.from(encodedPayload, 'base64url').toString('utf8'));
  } catch {
    return null;
  }

  if (typeof claims.exp !== 'number' || claims.exp <= Math.floor(Date.now() / 1000)) {
    return null;
  }

  return claims;
}

/**
 * A refresh token, for shape only.
 *
 * The response body must match the contract, so the field is present. It is
 * random, it is not stored, and presenting it to this stub does nothing: there
 * is no `/auth/refresh` here. The contract gives a refresh token a seven-day
 * life; the stub has nowhere to record that. Sprint 8 adds storage, rotation and
 * revocation, and that is where the interesting part of the lifecycle lives.
 */
function issueRefreshToken() {
  return createHash('sha256')
    .update(`${Date.now()}:${Math.random()}`)
    .digest('hex');
}

// -----------------------------------------------------------------------------
// HTTP handling
//
// Node's built-in http module, no framework. A request arrives as a stream, so
// the body is collected before it can be parsed.
// -----------------------------------------------------------------------------

function sendJson(response, status, body) {
  const payload = JSON.stringify(body);
  response.writeHead(status, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(payload),
    // Tokens must not be cached by a browser or a proxy.
    'Cache-Control': 'no-store',
  });
  response.end(payload);
}

function sendError(response, error) {
  sendJson(response, error.status, error.body);
}

/** Collects the request body, with a cap so that a large POST cannot exhaust memory. */
function readJsonBody(request, limitBytes = 8192) {
  return new Promise((resolve) => {
    let size = 0;
    const chunks = [];

    request.on('data', (chunk) => {
      size += chunk.length;
      if (size > limitBytes) {
        request.destroy();
        resolve(null);
        return;
      }
      chunks.push(chunk);
    });

    request.on('end', () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'));
      } catch {
        resolve(null);
      }
    });

    request.on('error', () => resolve(null));
  });
}

/**
 * POST /auth/login
 *
 * Checks the username against the five demo users and the password against the
 * one shared value. A real service hashes with argon2 and compares hashes; this
 * one compares strings, which is exactly what Sprint 8 replaces.
 */
async function handleLogin(request, response) {
  const body = await readJsonBody(request);

  if (!body || typeof body.username !== 'string' || typeof body.password !== 'string') {
    sendError(response, ERRORS.invalidInput);
    return;
  }

  const user = DEMO_USERS.find((candidate) => candidate.username === body.username);

  // One branch, one response. Note that the unknown-user case and the
  // wrong-password case fall into the same `if`, on purpose.
  if (!user || body.password !== DEMO_PASSWORD) {
    process.stdout.write(
      `${JSON.stringify({ level: 'warn', event: 'login.failed', username: body.username, service: 'auth-stub' })}\n`,
    );
    sendError(response, ERRORS.unauthorised);
    return;
  }

  const { token, expiresIn } = issueAccessToken(user);

  sendJson(response, 200, {
    accessToken: token,
    refreshToken: issueRefreshToken(),
    tokenType: 'Bearer',
    expiresIn,
  });
}

/**
 * GET /auth/me
 *
 * The identity comes from the verified token and from nowhere else. A version of
 * this endpoint that read a username from a query parameter would let any caller
 * ask about any user, which is OWASP A01, broken access control.
 */
function handleMe(request, response) {
  const header = request.headers.authorization || '';
  const [scheme, token, ...rest] = header.split(' ');

  if (rest.length > 0 || scheme.toLowerCase() !== 'bearer' || !token) {
    sendError(response, ERRORS.unauthorised);
    return;
  }

  const claims = verifyAccessToken(token);
  if (!claims) {
    sendError(response, ERRORS.unauthorised);
    return;
  }

  const user = DEMO_USERS.find((candidate) => candidate.id === claims.sub);
  if (!user) {
    sendError(response, ERRORS.unauthorised);
    return;
  }

  sendJson(response, 200, {
    id: user.id,
    username: user.username,
    accountId: user.accountId,
    roles: user.roles,
  });
}

/** Routes two paths. Everything else is a 404 carrying the platform envelope. */
function createServer() {
  return http.createServer((request, response) => {
    const path = (request.url || '').split('?')[0];

    if (request.method === 'POST' && path === '/auth/login') {
      handleLogin(request, response).catch(() => sendError(response, ERRORS.unauthorised));
      return;
    }

    if (request.method === 'GET' && path === '/auth/me') {
      handleMe(request, response);
      return;
    }

    // /auth/register and /auth/refresh are in the contract and are not
    // implemented here. Sprint 8 implements all four.
    sendError(response, ERRORS.notFound);
  });
}

// Started only when this file is run directly, so that the parity test can
// import the signing functions without opening a port.
if (require.main === module) {
  createServer().listen(PORT, '0.0.0.0', () => {
    process.stdout.write(
      `${JSON.stringify({
        level: 'info',
        event: 'service.started',
        service: 'auth-stub',
        port: PORT,
        issuer: ISSUER,
        users: DEMO_USERS.map((user) => user.username),
      })}\n`,
    );
  });
}

module.exports = {
  createServer,
  issueAccessToken,
  verifyAccessToken,
  signJwt,
  demoUserId,
  DEMO_USERS,
  DEMO_PASSWORD,
  DEMO_USER_NAMESPACE,
  ACCESS_TOKEN_TTL_SECONDS,
  ISSUER,
  PORT,
};

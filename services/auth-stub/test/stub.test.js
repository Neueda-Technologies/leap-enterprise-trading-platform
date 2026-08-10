/**
 * Smoke tests for the stub.
 *
 * The stub is a fixture and carries no assessment, so these exist for one
 * reason: to prove the fixture works before a participant spends an afternoon
 * deciding whether their Spring Boot verification code is wrong. Run them with
 * `npm test`. They use Node's built-in test runner, so there is nothing to
 * install.
 */

'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

// The stub reads the secret at load time, so it is set before the require.
process.env.JWT_SECRET = 'development-only-shared-secret-change-me';

const { createServer, DEMO_PASSWORD, DEMO_USERS, verifyAccessToken } = require('../src/server');

/** Starts the stub on a free port and returns a base URL plus a stop function. */
async function startServer() {
  const server = createServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  return {
    url: `http://127.0.0.1:${port}`,
    stop: () => new Promise((resolve) => server.close(resolve)),
  };
}

async function login(url, username, password) {
  const response = await fetch(`${url}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password }),
  });
  return { status: response.status, body: await response.json() };
}

test('login returns a token pair for every demo user', async () => {
  const server = await startServer();
  try {
    for (const user of DEMO_USERS) {
      const { status, body } = await login(server.url, user.username, DEMO_PASSWORD);

      assert.equal(status, 200);
      assert.deepEqual(Object.keys(body).sort(), ['accessToken', 'expiresIn', 'refreshToken', 'tokenType']);
      assert.equal(body.tokenType, 'Bearer');
      assert.equal(body.expiresIn, 900);

      const claims = verifyAccessToken(body.accessToken);
      assert.equal(claims.sub, user.id);
      assert.equal(claims.accountId, user.accountId);
      assert.deepEqual(claims.roles, ['CUSTOMER']);
      assert.equal(claims.iss, 'auth-stub');
      assert.equal(claims.exp - claims.iat, 900);
    }
  } finally {
    await server.stop();
  }
});

test('an unknown user and a wrong password return the same body', async () => {
  const server = await startServer();
  try {
    const unknown = await login(server.url, 'nobody', DEMO_PASSWORD);
    const wrong = await login(server.url, 'demo1', 'not-the-password');

    assert.equal(unknown.status, 401);
    assert.equal(wrong.status, 401);
    assert.deepEqual(unknown.body, { errorCode: 'AUTH-401', message: 'Unauthorised' });
    assert.deepEqual(wrong.body, unknown.body);
  } finally {
    await server.stop();
  }
});

test('a body missing a field is VAL-422', async () => {
  const server = await startServer();
  try {
    const response = await fetch(`${server.url}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'demo1' }),
    });

    assert.equal(response.status, 422);
    assert.deepEqual(await response.json(), { errorCode: 'VAL-422', message: 'Invalid input' });
  } finally {
    await server.stop();
  }
});

test('me returns the user behind a valid token', async () => {
  const server = await startServer();
  try {
    const { body } = await login(server.url, 'demo3', DEMO_PASSWORD);
    const response = await fetch(`${server.url}/auth/me`, {
      headers: { Authorization: `Bearer ${body.accessToken}` },
    });

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      id: DEMO_USERS[2].id,
      username: 'demo3',
      accountId: 3,
      roles: ['CUSTOMER'],
    });
  } finally {
    await server.stop();
  }
});

test('me rejects a missing header, a wrong scheme and a tampered token', async () => {
  const server = await startServer();
  try {
    const { body } = await login(server.url, 'demo1', DEMO_PASSWORD);
    const [header, payload, signature] = body.accessToken.split('.');
    const elevated = Buffer.from(
      JSON.stringify({
        sub: DEMO_USERS[0].id,
        accountId: 1,
        roles: ['ADMIN'],
        iat: Math.floor(Date.now() / 1000),
        exp: Math.floor(Date.now() / 1000) + 900,
        iss: 'auth-stub',
      }),
    ).toString('base64url');

    const cases = [
      {},
      { Authorization: 'Basic ZGVtbzE6cGFzcw==' },
      { Authorization: `Bearer ${header}.${elevated}.${signature}` },
      { Authorization: `Bearer ${header}.${payload}.${'a'.repeat(43)}` },
    ];

    for (const headers of cases) {
      const response = await fetch(`${server.url}/auth/me`, { headers });
      assert.equal(response.status, 401);
      assert.deepEqual(await response.json(), { errorCode: 'AUTH-401', message: 'Unauthorised' });
    }
  } finally {
    await server.stop();
  }
});

test('an expired token is rejected', async () => {
  const { issueAccessToken } = require('../src/server');
  const expired = issueAccessToken(DEMO_USERS[0], Math.floor(Date.now() / 1000) - 1000);

  assert.equal(verifyAccessToken(expired.token), null);
});

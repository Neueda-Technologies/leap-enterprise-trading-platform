import { Page, expect, test } from '@playwright/test';

/**
 * Support for specs that need the platform running.
 *
 * A cohort runs these on laptops where Docker Compose may or may not be up. A suite that
 * fails with a connection error tells nobody anything, so the specs check first and skip with
 * a readable reason. A skip is honest. A green run against a service that is not there is not.
 */

const TRADE_API = process.env['E2E_TRADE_API'] ?? 'http://localhost:8080';
const AUTH_API = process.env['E2E_AUTH_API'] ?? 'http://localhost:3000';

/** Credentials for the seeded user. Override for a differently seeded database. */
export const CREDENTIALS = {
  username: process.env['E2E_USERNAME'] ?? 'priya.menon',
  password: process.env['E2E_PASSWORD'] ?? 'correct horse battery staple',
};

let probe: Promise<boolean> | null = null;

/**
 * True when both services answer.
 *
 * Any HTTP response counts as reachable, including 401 and 422. The question is whether
 * something is listening, not whether the request was valid.
 */
export function platformIsRunning(): Promise<boolean> {
  probe ??= Promise.all([
    responds(`${AUTH_API}/auth/login`, 'POST'),
    responds(`${TRADE_API}/api/v1/accounts/1`, 'GET'),
  ]).then((results) => results.every(Boolean));

  return probe;
}

/** Put in a `beforeEach` of any suite that needs live services. */
export async function skipWithoutPlatform(): Promise<void> {
  test.skip(
    !(await platformIsRunning()),
    `The Trade REST API (${TRADE_API}) or the Auth service (${AUTH_API}) is not reachable. ` +
      'Start the platform with docker compose up, then run this suite again.',
  );
}

/** Sign in through the real form, because that is the flow under test. */
export async function signIn(page: Page): Promise<void> {
  await page.goto('/login');
  await page.getByLabel('Username').fill(CREDENTIALS.username);
  await page.getByLabel('Password').fill(CREDENTIALS.password);
  await page.getByTestId('login-submit').click();
  await expect(page).toHaveURL(/\/dashboard/);
}

async function responds(url: string, method: string): Promise<boolean> {
  try {
    await fetch(url, {
      method,
      headers: { 'content-type': 'application/json' },
      body: method === 'POST' ? '{}' : undefined,
      signal: AbortSignal.timeout(2000),
    });
    return true;
  } catch {
    return false;
  }
}

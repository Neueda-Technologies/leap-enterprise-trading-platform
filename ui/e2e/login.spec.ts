import { expect, test } from '@playwright/test';

import { CREDENTIALS, skipWithoutPlatform } from './support/platform';

/**
 * The route guard needs no backend, so this group always runs. It is also the fastest way to
 * tell whether the dev server itself is healthy.
 */
test.describe('route protection', () => {
  test('sends a signed-out visitor from the dashboard to sign-in', async ({ page }) => {
    await page.goto('/dashboard');

    await expect(page).toHaveURL(/\/login\?redirectTo=%2Fdashboard/);
    await expect(page.getByRole('heading', { name: 'Enterprise Trading Platform' })).toBeVisible();
  });

  test('sends a signed-out visitor from the order ticket to sign-in', async ({ page }) => {
    await page.goto('/orders/new');
    await expect(page).toHaveURL(/\/login\?redirectTo=%2Forders%2Fnew/);
  });
});

test.describe('sign in', () => {
  test.beforeEach(skipWithoutPlatform);

  test('rejects wrong credentials with one message', async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel('Username').fill(CREDENTIALS.username);
    await page.getByLabel('Password').fill('not the password');
    await page.getByTestId('login-submit').click();

    // The Auth service returns the same AUTH-401 body for a wrong password and for an unknown
    // user, so this message must not reveal which one it was.
    await expect(page.getByTestId('login-error')).toBeVisible();
    await expect(page).toHaveURL(/\/login/);
  });

  test('signs in and lands on the dashboard', async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel('Username').fill(CREDENTIALS.username);
    await page.getByLabel('Password').fill(CREDENTIALS.password);
    await page.getByTestId('login-submit').click();

    await expect(page).toHaveURL(/\/dashboard/);
    await expect(page.getByTestId('welcome-banner')).toContainText('Welcome');
    await expect(page.getByTestId('balance-card')).toBeVisible();
  });

  test('returns to the requested screen after signing in', async ({ page }) => {
    await page.goto('/orders');
    await page.getByLabel('Username').fill(CREDENTIALS.username);
    await page.getByLabel('Password').fill(CREDENTIALS.password);
    await page.getByTestId('login-submit').click();

    await expect(page).toHaveURL(/\/orders$/);
  });

  test('logging out clears the session', async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel('Username').fill(CREDENTIALS.username);
    await page.getByLabel('Password').fill(CREDENTIALS.password);
    await page.getByTestId('login-submit').click();
    await expect(page).toHaveURL(/\/dashboard/);

    await page.getByTestId('logout').click();
    await expect(page).toHaveURL(/\/login/);

    // Going back to a protected screen must not restore the session.
    await page.goto('/dashboard');
    await expect(page).toHaveURL(/\/login/);
  });
});

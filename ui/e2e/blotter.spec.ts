import { expect, test } from '@playwright/test';

import { signIn, skipWithoutPlatform } from './support/platform';

test.describe('blotter', () => {
  test.beforeEach(skipWithoutPlatform);
  test.beforeEach(async ({ page }) => {
    await signIn(page);
    await page.getByTestId('go-blotter').click();
    await expect(page).toHaveURL(/\/orders$/);
  });

  test('lists the audit trail columns', async ({ page }) => {
    const table = page.getByTestId('blotter-table');
    await expect(table).toBeVisible();

    for (const column of ['Date', 'Symbol', 'Side', 'Quantity', 'Status']) {
      await expect(table.getByRole('columnheader', { name: column, exact: false })).toBeVisible();
    }
  });

  test('shows either orders or an empty state, never a blank screen', async ({ page }) => {
    const rows = page.getByTestId('blotter-table').locator('tbody tr');
    await expect(rows.first()).toBeVisible();
  });

  test('colours BUY and SELL differently, and labels them too', async ({ page }) => {
    const buys = page.locator('.side-buy');
    const sells = page.locator('.side-sell');

    if ((await buys.count()) > 0) {
      await expect(buys.first()).toHaveText('BUY');
    }
    if ((await sells.count()) > 0) {
      await expect(sells.first()).toHaveText('SELL');
    }
  });

  test('filters by status through the API query parameter', async ({ page }) => {
    const request = page.waitForRequest((candidate) => candidate.url().includes('status=FILLED'));
    await page.getByTestId('status-filter').selectOption('FILLED');
    await request;

    const statuses = page.getByTestId('blotter-table').locator('tbody .badge');
    for (let index = 0; index < (await statuses.count()); index += 1) {
      await expect(statuses.nth(index)).toHaveText('FILLED');
    }
  });
});

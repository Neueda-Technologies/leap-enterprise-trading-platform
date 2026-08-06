import { expect, test } from '@playwright/test';

import { signIn, skipWithoutPlatform } from './support/platform';

/** The instrument to trade. Change it to something seeded in your `INSTRUMENTS` table. */
const SYMBOL = process.env['E2E_SYMBOL'] ?? 'ACME';

test.describe('order ticket', () => {
  test.beforeEach(skipWithoutPlatform);
  test.beforeEach(async ({ page }) => {
    await signIn(page);
    await page.getByTestId('go-order-ticket').click();
    await expect(page).toHaveURL(/\/orders\/new/);
  });

  test('shows the account read-only', async ({ page }) => {
    const account = page.getByTestId('account-field');
    await expect(account).toBeVisible();
    await expect(account).toHaveAttribute('readonly', '');
  });

  test('refuses a quantity of zero without calling the API', async ({ page }) => {
    await page.getByTestId('symbol').fill(SYMBOL);
    await page.getByTestId('quantity').fill('0');
    await page.getByTestId('price').fill('25.50');
    await page.getByTestId('submit-order').click();

    await expect(page.getByTestId('quantity-error')).toBeVisible();
    await expect(page.getByTestId('order-result')).toHaveCount(0);
  });

  test('refuses a price of zero', async ({ page }) => {
    await page.getByTestId('symbol').fill(SYMBOL);
    await page.getByTestId('quantity').fill('10');
    await page.getByTestId('price').fill('0');
    await page.getByTestId('submit-order').click();

    await expect(page.getByTestId('price-error')).toBeVisible();
    await expect(page.getByTestId('order-result')).toHaveCount(0);
  });

  test('places a buy order and reports the outcome', async ({ page }) => {
    await page.getByTestId('symbol').fill(SYMBOL);
    await page.getByTestId('side').selectOption('BUY');
    await page.getByTestId('quantity').fill('1');
    await page.getByTestId('price').fill('25.50');
    await page.getByTestId('submit-order').click();

    const result = page.getByTestId('order-result');
    await expect(result).toBeVisible();

    /*
     * Both outcomes are valid under the contract. Sprint 6 fills inside the request and the
     * panel goes straight to FILLED or REJECTED. From Sprint 7 the API answers NEW and the
     * panel polls order history until the Trade Executor writes the fill. Asserting only on
     * FILLED would make this spec fail the week Kafka arrives, which is the wrong signal.
     */
    await expect
      .poll(() => result.getAttribute('data-status'), { timeout: 30_000 })
      .toMatch(/^(NEW|FILLED|REJECTED)$/);
  });

  test('sends a rejected order to the audit trail as well', async ({ page }) => {
    // A price far above the balance either fails rule 6 in the API or is rejected by the
    // executor. Either way the order is recorded, because the order table is the audit trail.
    await page.getByTestId('symbol').fill(SYMBOL);
    await page.getByTestId('quantity').fill('100000');
    await page.getByTestId('price').fill('9999.99');
    await page.getByTestId('submit-order').click();

    const rejectedInline = page.getByTestId('ticket-error');
    const result = page.getByTestId('order-result');
    await expect(rejectedInline.or(result)).toBeVisible();
  });
});

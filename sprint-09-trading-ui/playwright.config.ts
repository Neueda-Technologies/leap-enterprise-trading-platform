import { defineConfig, devices } from '@playwright/test';

/**
 * End-to-end configuration.
 *
 * The journeys drive a real browser against your running platform: your Angular build, your
 * Trade REST API and your Auth service. That is the point of them. Unit tests already cover
 * the pieces, and an end-to-end test that talks to a stub proves nothing about integration.
 *
 * Playwright starts the dev server when one is not already listening, so `npm run e2e` works
 * from a cold checkout. It does not start your backend, because Playwright is not a container
 * orchestrator. Bring the stack up first with `docker compose up -d` from the repository root.
 *
 * Every address the suite needs is read here and nowhere else. A spec that hard-codes
 * `http://localhost:8080` cannot be pointed at a deployed environment in Sprint 11.
 */

/** The application under test. Set E2E_BASE_URL to run against a deployed build. */
const baseURL = process.env['E2E_BASE_URL'] ?? 'http://localhost:4200';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env['CI'],
  retries: process.env['CI'] ? 1 : 0,
  workers: process.env['CI'] ? 1 : undefined,
  reporter: process.env['CI'] ? [['html', { open: 'never' }]] : [['list']],

  use: {
    baseURL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },

  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],

  /*
   * Skipped when E2E_BASE_URL points elsewhere, because something is already serving there.
   */
  webServer: process.env['E2E_BASE_URL']
    ? undefined
    : {
        command: 'npm start',
        url: 'http://localhost:4200',
        reuseExistingServer: !process.env['CI'],
        timeout: 120_000,
      },
});

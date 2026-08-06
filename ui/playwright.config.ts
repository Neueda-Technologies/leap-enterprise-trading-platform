import { defineConfig, devices } from '@playwright/test';

/**
 * End-to-end configuration.
 *
 * The specs drive a real browser against a real Trade REST API and a real Auth service, both
 * from Docker Compose. That is the point of them: unit tests already cover the pieces, and an
 * end-to-end test that talks to stubs proves nothing about integration.
 *
 * The dev server is started here when one is not already running, so `npm run e2e` works from
 * a cold checkout. Backend services are not started here, because Playwright is not a
 * container orchestrator. When they are absent the specs skip themselves with a message; see
 * `e2e/support/platform.ts`.
 *
 * Override the target with `E2E_BASE_URL` to run against a deployed build.
 */
const baseURL = process.env['E2E_BASE_URL'] ?? 'http://localhost:4200';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env['CI'],
  retries: process.env['CI'] ? 1 : 0,
  workers: process.env['CI'] ? 1 : undefined,
  reporter: process.env['CI'] ? [['github'], ['html', { open: 'never' }]] : [['list']],

  use: {
    baseURL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },

  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],

  // Skipped when E2E_BASE_URL points somewhere else, such as a deployed environment.
  webServer: process.env['E2E_BASE_URL']
    ? undefined
    : {
        command: 'npm start',
        url: 'http://localhost:4200',
        reuseExistingServer: !process.env['CI'],
        timeout: 120_000,
      },
});

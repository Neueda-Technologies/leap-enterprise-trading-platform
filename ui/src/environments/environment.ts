/*
 * Configuration used by `ng build`, which defaults to the production configuration.
 * `ng serve` swaps this file for `environment.development.ts` through the
 * `fileReplacements` entry in `angular.json`. Keep the two files in step: a key added
 * here and not there is a runtime `undefined` that the compiler will not catch.
 *
 * The values below point at a local Docker Compose stack so that a production build
 * can be smoke-tested on a laptop. Sprint 11 replaces this file at build time with the
 * deployed origins before the bundle is uploaded to S3.
 */
export const environment = {
  production: true,

  /** Trade REST API, `docs/contracts/trade-api.yaml`. */
  tradeApiBaseUrl: 'http://localhost:8080',

  /**
   * Auth service, `docs/contracts/auth-api.yaml`. The NestJS service and the provided
   * Node auth stub are interchangeable and both listen on 3000, so swapping one for the
   * other is a change to this line only. A team running both side by side during the
   * Sprint 8 cutover puts the stub on 3001 and points this at whichever one it is testing.
   */
  authApiBaseUrl: 'http://localhost:3000',

  /** How often the order ticket re-reads order history while an order is still NEW. */
  orderPollIntervalMs: 2000,

  /** How many times it re-reads before it gives up and tells the user to check the blotter. */
  orderPollAttempts: 10,
};

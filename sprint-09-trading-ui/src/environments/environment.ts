/*
 * Configuration compiled into the production bundle. `ng build` defaults to the production
 * configuration and uses this file. `ng serve` swaps it for `environment.development.ts`
 * through the `fileReplacements` entry in `angular.json`. Keep the two in step: a key added
 * to one and not the other is a runtime `undefined` the compiler cannot see.
 *
 * Everything in this file is public. The bundle is downloaded by every browser that opens
 * the application, and anyone can read it. No API key, no signing secret and no Fauxnance
 * base URL belongs here or anywhere else under src/. Prices reach the browser through your
 * own services, never from the browser calling the market-data API.
 *
 * Sprint 11 replaces this file at build time with the deployed origins.
 */
export const environment = {
  production: true,

  /** Trade REST API, from `contracts/trade-api.yaml`. */
  tradeApiBaseUrl: 'http://localhost:8080',

  /** Auth service, from `contracts/auth-api.yaml`. */
  authApiBaseUrl: 'http://localhost:3000',
};

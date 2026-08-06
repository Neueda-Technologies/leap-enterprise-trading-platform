/*
 * Configuration used by `ng serve` and by `ng build --configuration development`.
 * Mirrors `environment.ts`. See the comments there for what each key means.
 */
export const environment = {
  production: false,
  tradeApiBaseUrl: 'http://localhost:8080',
  authApiBaseUrl: 'http://localhost:3000',
  orderPollIntervalMs: 2000,
  orderPollAttempts: 10,
};

/*
 * Configuration used by `ng serve` and by `ng build --configuration development`.
 *
 * The two origins below are the compose stack on your own machine. A team running the
 * Sprint 8 cutover with the retired stub on 3001 points `authApiBaseUrl` at whichever of
 * the two it is testing, and changes nothing else. That single line is the whole of the
 * "no code change in the Angular application" criterion.
 */
export const environment = {
  production: false,

  /** Trade REST API, from `contracts/trade-api.yaml`. */
  tradeApiBaseUrl: 'http://localhost:8080',

  /** Auth service, from `contracts/auth-api.yaml`. */
  authApiBaseUrl: 'http://localhost:3000',
};

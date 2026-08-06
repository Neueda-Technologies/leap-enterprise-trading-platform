/**
 * Injection token for the shared pg connection pool.
 *
 * A string token rather than the Pool class itself, so that a test can provide a
 * fake without importing pg and without a running database.
 */
export const PG_POOL = 'PG_POOL';

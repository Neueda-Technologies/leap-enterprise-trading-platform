/**
 * Environment configuration for the auth service.
 *
 * Everything the service needs to run is read here, once, and validated at boot.
 * A service that reads process.env from twenty files fails at the moment the
 * twenty-first request needs the variable nobody set.
 */

export interface AuthConfig {
  port: number;
  nodeEnv: string;
  jwt: {
    secret: string;
    issuer: string;
    accessTokenTtlSeconds: number;
    refreshTokenTtlSeconds: number;
  };
  database: {
    connectionString?: string;
    host: string;
    port: number;
    user: string;
    password: string;
    database: string;
    maxConnections: number;
  };
  bootstrap: {
    runMigrations: boolean;
    seedDemoUsers: boolean;
  };
  login: {
    throttleTtlSeconds: number;
    throttleLimit: number;
  };
}

/** The development secret shipped in .env.example. Refused outside development. */
export const DEV_SECRET = 'development-only-shared-secret-change-me';

function readInt(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === '') {
    return fallback;
  }
  const value = Number.parseInt(raw, 10);
  if (Number.isNaN(value)) {
    throw new Error(`${name} must be an integer, received "${raw}"`);
  }
  return value;
}

function readBool(name: string, fallback: boolean): boolean {
  const raw = process.env[name];
  if (raw === undefined || raw === '') {
    return fallback;
  }
  return raw.toLowerCase() === 'true' || raw === '1';
}

/**
 * Builds the configuration object and refuses to start on a bad environment.
 *
 * Failing at boot is deliberate. A missing JWT_SECRET discovered at the first
 * login is a production incident; discovered at boot it is a failed deployment,
 * which is the cheaper of the two.
 */
export function loadConfiguration(): AuthConfig {
  const nodeEnv = process.env.NODE_ENV ?? 'development';
  const secret = process.env.JWT_SECRET;

  if (!secret) {
    throw new Error('JWT_SECRET is not set. The service cannot sign tokens without it.');
  }
  if (secret.length < 32) {
    throw new Error('JWT_SECRET must be at least 32 characters. A short HS256 secret is brute-forceable offline.');
  }
  if (nodeEnv === 'production' && secret === DEV_SECRET) {
    throw new Error('JWT_SECRET is the shared development secret. Set a real secret in production.');
  }

  return {
    port: readInt('PORT', 3000),
    nodeEnv,
    jwt: {
      secret,
      issuer: process.env.JWT_ISSUER ?? 'auth-service',
      accessTokenTtlSeconds: readInt('ACCESS_TOKEN_TTL_SECONDS', 900),
      refreshTokenTtlSeconds: readInt('REFRESH_TOKEN_TTL_SECONDS', 604800),
    },
    database: {
      connectionString: process.env.DATABASE_URL,
      host: process.env.PGHOST ?? 'localhost',
      port: readInt('PGPORT', 5432),
      user: process.env.PGUSER ?? 'postgres',
      password: process.env.PGPASSWORD ?? 'postgres',
      database: process.env.PGDATABASE ?? 'trading',
      maxConnections: readInt('PGPOOL_MAX', 10),
    },
    bootstrap: {
      runMigrations: readBool('AUTH_RUN_MIGRATIONS', true),
      seedDemoUsers: readBool('AUTH_SEED_DEMO_USERS', false),
    },
    login: {
      throttleTtlSeconds: readInt('LOGIN_THROTTLE_TTL_SECONDS', 60),
      throttleLimit: readInt('LOGIN_THROTTLE_LIMIT', 5),
    },
  };
}

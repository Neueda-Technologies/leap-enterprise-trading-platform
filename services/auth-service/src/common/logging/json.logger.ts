import { ConsoleLogger, LoggerService, LogLevel } from '@nestjs/common';

/**
 * One JSON object per line on stdout.
 *
 * Structured logging is not decoration. A log aggregator can filter
 * `event="login.failed"` across every replica; it cannot usefully filter free
 * text. The redaction pass below is the part that matters most on this service:
 * the auth service is the only component that ever holds a password, and a
 * password reaching a log file is a reportable incident even if the file is
 * private.
 */

const REDACTED = '[redacted]';

const SENSITIVE_KEYS = new Set([
  'password',
  'passwordhash',
  'password_hash',
  'token',
  'accesstoken',
  'refreshtoken',
  'authorization',
  'secret',
  'jwt_secret',
]);

/** Replaces the value of any sensitive key, at any depth, before it is written. */
export function redact(value: unknown, depth = 0): unknown {
  if (depth > 6 || value === null || typeof value !== 'object') {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((item) => redact(item, depth + 1));
  }
  const output: Record<string, unknown> = {};
  for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
    output[key] = SENSITIVE_KEYS.has(key.toLowerCase()) ? REDACTED : redact(entry, depth + 1);
  }
  return output;
}

export class JsonLogger extends ConsoleLogger implements LoggerService {
  private readonly service: string;

  constructor(service = 'auth-service') {
    super();
    this.service = service;
  }

  log(message: unknown, ...rest: unknown[]): void {
    this.emit('info', message, rest);
  }

  error(message: unknown, ...rest: unknown[]): void {
    this.emit('error', message, rest);
  }

  warn(message: unknown, ...rest: unknown[]): void {
    this.emit('warn', message, rest);
  }

  debug(message: unknown, ...rest: unknown[]): void {
    this.emit('debug', message, rest);
  }

  verbose(message: unknown, ...rest: unknown[]): void {
    this.emit('verbose', message, rest);
  }

  private emit(level: LogLevel | 'info', message: unknown, rest: unknown[]): void {
    const context = rest.find((item) => typeof item === 'string');
    const detail = rest.find((item) => typeof item === 'object' && item !== null);

    const line = {
      timestamp: new Date().toISOString(),
      level,
      service: this.service,
      context: context ?? this.context ?? 'application',
      message: typeof message === 'string' ? message : JSON.stringify(redact(message)),
      ...(detail ? { detail: redact(detail) } : {}),
    };

    process.stdout.write(`${JSON.stringify(line)}\n`);
  }
}

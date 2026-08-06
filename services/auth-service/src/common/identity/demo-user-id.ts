import { createHash } from 'node:crypto';

/**
 * Deterministic identifiers for the demo users.
 *
 * The demo accounts exist in two implementations: this service, which stores
 * them, and the Sprint 6 auth stub, which has no database at all. If the two
 * derived different `sub` values for `demo1`, a token issued by the stub would
 * name a user the real service has never heard of, and the Sprint 8 cutover
 * would stop being a configuration change.
 *
 * A name-based UUID (RFC 4122 version 5) solves it without either side calling
 * the other: both compute the same UUID from the same namespace and username.
 * The stub carries its own copy of this function. The duplication is deliberate:
 * the stub must stay dependency-free and must keep working after this service
 * replaces it.
 */

/** Fixed namespace for platform demo users. Changing it changes every demo `sub`. */
export const DEMO_USER_NAMESPACE = 'a1e3c9f2-5b7d-4c8e-9f10-2b6d4e8a7c31';

export function demoUserId(username: string, namespace: string = DEMO_USER_NAMESPACE): string {
  const namespaceBytes = Buffer.from(namespace.replace(/-/g, ''), 'hex');
  const digest = createHash('sha1').update(namespaceBytes).update(Buffer.from(username, 'utf8')).digest();

  const bytes = Buffer.from(digest.subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50; // version 5
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant

  const hex = bytes.toString('hex');
  return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join('-');
}

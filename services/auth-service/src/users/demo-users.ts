import { demoUserId } from '../common/identity/demo-user-id';
import { Role } from './role.enum';

/**
 * The five demo logins used across the programme.
 *
 * They map one to one onto the seeded trading accounts `ACCOUNTS.id` 1 to 5, so
 * a participant can log in as `demo3` and immediately place an order against
 * account 3. The Sprint 6 auth stub serves the same five with the same password
 * and the same identifiers.
 *
 * Seeding is opt-in through AUTH_SEED_DEMO_USERS. A shared password committed to
 * a repository is acceptable in a training environment and nowhere else, which
 * is why the flag defaults to false and the README says so.
 */

export const DEMO_PASSWORD = 'Trainee#2026';

export interface DemoUser {
  id: string;
  username: string;
  accountId: number;
  roles: Role[];
}

export const DEMO_USERS: DemoUser[] = [1, 2, 3, 4, 5].map((accountId) => {
  const username = `demo${accountId}`;
  return {
    id: demoUserId(username),
    username,
    accountId,
    roles: [Role.CUSTOMER],
  };
});

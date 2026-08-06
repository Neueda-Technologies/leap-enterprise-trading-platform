import { Role } from './role.enum';

/**
 * A row of `auth.users` as the service sees it.
 *
 * `passwordHash` is on this type because the repository returns it and the
 * credential check needs it. It is never on `UserResponseDto`, which is the type
 * that reaches a client. Keeping the two types separate is what stops a hash
 * being serialised by an endpoint that returns "the user".
 */
export interface UserRecord {
  id: string;
  username: string;
  passwordHash: string;
  accountId: number;
  roles: Role[];
  createdOn: Date;
}

/** The subset of a user that the token service and the guard need. */
export interface AuthenticatedUser {
  id: string;
  username: string;
  accountId: number;
  roles: Role[];
}

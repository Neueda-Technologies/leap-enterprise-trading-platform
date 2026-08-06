/**
 * Authorisation roles carried in the `roles` claim.
 *
 * The set is closed and matches `contracts/auth-api.yaml`. Adding a role means
 * changing the contract and the check constraint in `migrations/users.sql`, in
 * that order.
 */
export enum Role {
  CUSTOMER = 'CUSTOMER',
  ADMIN = 'ADMIN',
}

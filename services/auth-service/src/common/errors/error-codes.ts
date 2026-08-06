/**
 * The error catalogue for this service.
 *
 * Every failure leaves the service as `{ errorCode, message }` and nothing else.
 * The Angular UI branches on `errorCode`, never on the message or the status
 * line, so the codes are part of the contract and the messages are not.
 *
 * AUTH-401, AUTH-409 and VAL-422 are the three codes in `contracts/auth-api.yaml`.
 * AUTH-429 and AUTH-500 extend the catalogue and are scoped to this service, the
 * same way AUTH-409 extends the platform catalogue in `trade-api.yaml`. They
 * cover two failures the contract does not describe: login throttling, which
 * Sprint 8 requires, and an unhandled server fault, which every service has.
 * A client that does not recognise a code falls back to a generic message.
 */
export const ERROR_CODES = {
  UNAUTHORISED: 'AUTH-401',
  REGISTRATION_CONFLICT: 'AUTH-409',
  TOO_MANY_REQUESTS: 'AUTH-429',
  INTERNAL: 'AUTH-500',
  INVALID_INPUT: 'VAL-422',
} as const;

export type ErrorCode = (typeof ERROR_CODES)[keyof typeof ERROR_CODES];

/**
 * The only two failure messages the contract permits on the auth paths.
 *
 * "Unknown username" and "wrong password" are two facts an attacker would pay
 * for. Both paths return `Unauthorised`, and registration returns
 * `Registration failed` whether the username collided or the account did not
 * exist.
 */
export const ERROR_MESSAGES = {
  UNAUTHORISED: 'Unauthorised',
  REGISTRATION_FAILED: 'Registration failed',
  INVALID_INPUT: 'Invalid input',
  TOO_MANY_REQUESTS: 'Too many requests',
  INTERNAL: 'Internal error',
} as const;

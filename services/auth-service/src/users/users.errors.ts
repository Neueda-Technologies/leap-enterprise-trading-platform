/**
 * Persistence-layer failures, expressed in the language of the domain.
 *
 * The repository does not throw HTTP exceptions. A repository that throws
 * `ConflictException` cannot be reused by a command-line tool or a Kafka
 * consumer, and it hides the mapping from status code to cause in a file where
 * nobody looks for it.
 */

export class UsernameTakenError extends Error {
  constructor(username: string) {
    super(`username already registered: ${username}`);
    this.name = 'UsernameTakenError';
  }
}

export class UnknownAccountError extends Error {
  constructor(accountId: number) {
    super(`no trading account with id ${accountId}`);
    this.name = 'UnknownAccountError';
  }
}

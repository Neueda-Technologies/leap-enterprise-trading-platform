import { PasswordService } from './password.service';

/**
 * These run the real argon2 binding, not a mock. A mocked hash proves the code
 * calls a function; the point of the test is that the stored value is an
 * argon2id hash with a salt, which only the real library can demonstrate.
 *
 * argon2 is deliberately slow, so the timeout is raised.
 */
jest.setTimeout(30_000);

describe('PasswordService', () => {
  const passwords = new PasswordService();

  it('produces an argon2id hash carrying its own parameters and salt', async () => {
    const hash = await passwords.hash('Trainee#2026');

    expect(hash.startsWith('$argon2id$')).toBe(true);
    expect(hash).toContain('m=19456');
    expect(hash).toContain('t=2');
    expect(hash).toContain('p=1');
  });

  it('never stores the password itself', async () => {
    const hash = await passwords.hash('Trainee#2026');

    expect(hash).not.toContain('Trainee#2026');
  });

  it('produces a different hash every time, because the salt is random', async () => {
    const [first, second] = await Promise.all([passwords.hash('Trainee#2026'), passwords.hash('Trainee#2026')]);

    expect(first).not.toBe(second);
  });

  it('verifies the correct password', async () => {
    const hash = await passwords.hash('Trainee#2026');

    await expect(passwords.verify(hash, 'Trainee#2026')).resolves.toBe(true);
  });

  it.each([['Trainee#2027'], ['trainee#2026'], [''], ['Trainee#2026 ']])(
    'rejects the wrong password %p',
    async (attempt) => {
      const hash = await passwords.hash('Trainee#2026');

      await expect(passwords.verify(hash, attempt)).resolves.toBe(false);
    },
  );

  it('returns false rather than throwing on a stored value that is not a hash', async () => {
    await expect(passwords.verify('not-a-hash', 'Trainee#2026')).resolves.toBe(false);
  });

  it('always fails the dummy verification used for an unknown username', async () => {
    await expect(passwords.verifyDummy('Trainee#2026')).resolves.toBe(false);
    await expect(passwords.verifyDummy('')).resolves.toBe(false);
  });
});

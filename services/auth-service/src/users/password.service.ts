import { Injectable } from '@nestjs/common';
import * as argon2 from 'argon2';
import { randomBytes } from 'node:crypto';

/**
 * Password hashing and verification.
 *
 * argon2id, with the salt and the parameters encoded in the stored string, so a
 * later parameter change does not invalidate existing hashes. Cost is set high
 * enough to be felt: a login that takes 50 milliseconds of CPU is fine, and an
 * offline attacker running the same work per guess is the point.
 *
 * The parameters below are the OWASP Password Storage Cheat Sheet's argon2id
 * baseline: 19 MiB of memory, two iterations, one lane.
 */
@Injectable()
export class PasswordService {
  private readonly options: argon2.Options = {
    type: argon2.argon2id,
    memoryCost: 19456,
    timeCost: 2,
    parallelism: 1,
  };

  /** A hash of a value nobody knows, verified against when the username is unknown. */
  private readonly dummyHashPromise: Promise<string>;

  constructor() {
    this.dummyHashPromise = argon2.hash(randomBytes(32).toString('hex'), this.options);
  }

  async hash(plaintext: string): Promise<string> {
    return argon2.hash(plaintext, this.options);
  }

  async verify(hash: string, plaintext: string): Promise<boolean> {
    try {
      return await argon2.verify(hash, plaintext);
    } catch {
      // A stored value that is not a valid argon2 string is a failed
      // verification, not a server error. Returning false keeps the response
      // identical to a wrong password.
      return false;
    }
  }

  /**
   * Burns the same work as a real verification, and always fails.
   *
   * Call it when the username does not exist. Without it, an unknown user
   * returns in a millisecond and a known user with a wrong password returns in
   * fifty, and the difference is a username oracle that no amount of identical
   * response bodies will hide.
   */
  async verifyDummy(plaintext: string): Promise<false> {
    await this.verify(await this.dummyHashPromise, plaintext);
    return false;
  }
}

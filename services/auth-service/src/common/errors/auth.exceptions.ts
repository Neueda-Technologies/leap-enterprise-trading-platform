import { ConflictException, UnauthorizedException, UnprocessableEntityException } from '@nestjs/common';
import { ERROR_MESSAGES } from './error-codes';

/**
 * Domain exceptions, thrown by services, mapped to the envelope by
 * `AuthExceptionFilter`.
 *
 * They carry no cause and no detail on purpose. A service layer that throws
 * `new UnauthorisedException('user not found')` will eventually have that
 * string serialised to a client by an over-helpful error handler, and the
 * enumeration defence is gone.
 */

export class UnauthorisedException extends UnauthorizedException {
  constructor() {
    super(ERROR_MESSAGES.UNAUTHORISED);
  }
}

export class RegistrationConflictException extends ConflictException {
  constructor() {
    super(ERROR_MESSAGES.REGISTRATION_FAILED);
  }
}

export class InvalidInputException extends UnprocessableEntityException {
  constructor() {
    super(ERROR_MESSAGES.INVALID_INPUT);
  }
}

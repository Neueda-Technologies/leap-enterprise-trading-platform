import { ArgumentsHost, HttpException, HttpStatus } from '@nestjs/common';
import { AuthExceptionFilter } from './auth-exception.filter';
import { InvalidInputException, RegistrationConflictException, UnauthorisedException } from './auth.exceptions';
import { ERROR_CODES } from './error-codes';

function hostWith(): { host: ArgumentsHost; status: jest.Mock; json: jest.Mock } {
  const json = jest.fn();
  const status = jest.fn().mockReturnValue({ json });
  const host = {
    switchToHttp: () => ({
      getResponse: () => ({ status }),
      getRequest: () => ({ method: 'POST', url: '/auth/login' }),
    }),
  } as unknown as ArgumentsHost;
  return { host, status, json };
}

describe('AuthExceptionFilter', () => {
  const filter = new AuthExceptionFilter();

  it.each([
    [new UnauthorisedException(), HttpStatus.UNAUTHORIZED, ERROR_CODES.UNAUTHORISED, 'Unauthorised'],
    [
      new RegistrationConflictException(),
      HttpStatus.CONFLICT,
      ERROR_CODES.REGISTRATION_CONFLICT,
      'Registration failed',
    ],
    [new InvalidInputException(), HttpStatus.UNPROCESSABLE_ENTITY, ERROR_CODES.INVALID_INPUT, 'Invalid input'],
    [
      new HttpException('slow down', HttpStatus.TOO_MANY_REQUESTS),
      HttpStatus.TOO_MANY_REQUESTS,
      ERROR_CODES.TOO_MANY_REQUESTS,
      'Too many requests',
    ],
  ])('maps %p to the platform envelope', (exception, expectedStatus, errorCode, message) => {
    const { host, status, json } = hostWith();

    filter.catch(exception, host);

    expect(status).toHaveBeenCalledWith(expectedStatus);
    expect(json).toHaveBeenCalledWith({ errorCode, message });
  });

  it('never leaks the detail of an unexpected failure', () => {
    const { host, status, json } = hostWith();

    filter.catch(new Error('connection to postgres://user:secret@db refused'), host);

    expect(status).toHaveBeenCalledWith(HttpStatus.INTERNAL_SERVER_ERROR);
    expect(json).toHaveBeenCalledWith({ errorCode: ERROR_CODES.INTERNAL, message: 'Internal error' });
  });

  it('returns the envelope and nothing else, so the response carries no field list', () => {
    const { host, json } = hostWith();

    filter.catch(new UnauthorisedException(), host);

    expect(Object.keys(json.mock.calls[0][0])).toEqual(['errorCode', 'message']);
  });
});

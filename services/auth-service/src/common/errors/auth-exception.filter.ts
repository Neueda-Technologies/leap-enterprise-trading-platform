import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { Request, Response } from 'express';
import { ERROR_CODES, ERROR_MESSAGES } from './error-codes';

export interface ErrorEnvelope {
  errorCode: string;
  message: string;
}

/**
 * Turns every thrown thing into the platform error envelope.
 *
 * One filter, registered globally, is what keeps the envelope consistent. The
 * alternative, each controller catching and shaping its own errors, produces a
 * service where three routes return `{ error: "..." }`, one returns a stack
 * trace, and the UI needs a special case for each.
 *
 * Nothing from the thrown exception reaches the client except the mapped code
 * and the fixed message. A framework validation error lists the fields that
 * failed; on a login route that list tells an attacker which field was wrong.
 */
@Catch()
export class AuthExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(AuthExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const context = host.switchToHttp();
    const response = context.getResponse<Response>();
    const request = context.getRequest<Request>();

    const status = exception instanceof HttpException ? exception.getStatus() : HttpStatus.INTERNAL_SERVER_ERROR;
    const envelope = this.toEnvelope(status);

    if (status >= HttpStatus.INTERNAL_SERVER_ERROR) {
      // The full error is logged, never returned. The client gets AUTH-500.
      this.logger.error('request failed', {
        event: 'request.failed',
        method: request.method,
        path: request.url,
        status,
        error: exception instanceof Error ? exception.message : String(exception),
        stack: exception instanceof Error ? exception.stack : undefined,
      });
    } else {
      this.logger.warn('request rejected', {
        event: 'request.rejected',
        method: request.method,
        path: request.url,
        status,
        errorCode: envelope.errorCode,
      });
    }

    response.status(status).json(envelope);
  }

  private toEnvelope(status: number): ErrorEnvelope {
    switch (status) {
      case HttpStatus.UNAUTHORIZED:
      case HttpStatus.FORBIDDEN:
        // A bearer token that is valid but insufficient still returns AUTH-401
        // on this service: it exposes no route where the distinction matters.
        return { errorCode: ERROR_CODES.UNAUTHORISED, message: ERROR_MESSAGES.UNAUTHORISED };
      case HttpStatus.CONFLICT:
        return { errorCode: ERROR_CODES.REGISTRATION_CONFLICT, message: ERROR_MESSAGES.REGISTRATION_FAILED };
      case HttpStatus.BAD_REQUEST:
      case HttpStatus.UNPROCESSABLE_ENTITY:
        // A malformed body arrives as 400 from the body parser and as 422 from
        // the validation pipe. Both are the same failure to the client.
        return { errorCode: ERROR_CODES.INVALID_INPUT, message: ERROR_MESSAGES.INVALID_INPUT };
      case HttpStatus.TOO_MANY_REQUESTS:
        return { errorCode: ERROR_CODES.TOO_MANY_REQUESTS, message: ERROR_MESSAGES.TOO_MANY_REQUESTS };
      default:
        return { errorCode: ERROR_CODES.INTERNAL, message: ERROR_MESSAGES.INTERNAL };
    }
  }
}

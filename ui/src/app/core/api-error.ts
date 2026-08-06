import { HttpErrorResponse } from '@angular/common/http';
import { ErrorResponse } from './models/trade-api';

/**
 * A failure, normalised into something a template can render.
 *
 * Both contracts return the same envelope, `{ errorCode, message }`, so one function covers
 * every call in the application. `errorCode` is null when the failure never reached the
 * platform: a DNS failure, a CORS rejection or a dev server that is not running.
 */
export interface ApiError {
  /** HTTP status, or 0 when the request never got a response. */
  status: number;
  errorCode: string | null;
  message: string;
}

/**
 * Messages shown for the codes the UI can produce. The API's own `message` is deliberately
 * terse and, on the Auth service, deliberately vague, so the UI supplies the wording. Branch
 * on the code, never on the server's message string.
 */
const MESSAGES: Record<string, string> = {
  'AUTH-401': 'Sign-in failed. Check the username and password.',
  'AUTH-409': 'Registration failed.',
  'VAL-422': 'The order was rejected by field validation. Check the symbol, quantity and price.',
  'ACC-403': 'This account is not active, or this sign-in does not grant access to it.',
  'ACC-404': 'Account not found.',
  'INS-404': 'That instrument is not tradable.',
  'ORD-400': 'Insufficient funds for this buy order.',
  'ORD-409':
    'The order was rejected: insufficient holdings, or this order has already been placed.',
};

export function toApiError(error: unknown): ApiError {
  if (!(error instanceof HttpErrorResponse)) {
    return { status: 0, errorCode: null, message: 'Something went wrong. Try again.' };
  }

  if (error.status === 0) {
    return {
      status: 0,
      errorCode: null,
      message: 'The service is not reachable. Check that Docker Compose is running.',
    };
  }

  const body = error.error as Partial<ErrorResponse> | null;
  const code = typeof body?.errorCode === 'string' ? body.errorCode : null;

  return {
    status: error.status,
    errorCode: code,
    message:
      (code && MESSAGES[code]) || body?.message || `Request failed with status ${error.status}.`,
  };
}

import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { AuthenticatedRequest } from '../../auth/guards/jwt-auth.guard';
import { AuthenticatedUser } from '../../users/user.entity';

/**
 * Injects the identity that `JwtAuthGuard` verified.
 *
 * `@CurrentUser() user: AuthenticatedUser` reads only from what the guard
 * attached, which came only from a signature-checked token. That is the whole
 * point of the decorator: a handler that takes the user identifier from a path
 * parameter, a query string or a header is OWASP A01, broken access control, and
 * the decorator makes the safe route the shorter one to write.
 *
 * It throws if the guard did not run, rather than returning undefined, so the
 * mistake surfaces on the first request instead of as a null reference later.
 */
export const CurrentUser = createParamDecorator((_data: unknown, context: ExecutionContext): AuthenticatedUser => {
  const request = context.switchToHttp().getRequest<AuthenticatedRequest>();

  if (!request.user) {
    throw new Error('CurrentUser used on a route that is not behind JwtAuthGuard');
  }

  return request.user;
});

import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

import { AuthService } from '../services/auth-service';

/**
 * Keep unauthenticated users off the authenticated screens.
 *
 * This is a usability control, not a security control. The bundle is public and anyone can
 * read it, so the guard stops a signed-out user from loading a dashboard that would only show
 * a row of failed requests. The data behind it is protected by the API, which verifies the
 * token signature on every `/api/v1/**` route.
 *
 * Returning a `UrlTree` rather than calling `router.navigate` lets the router cancel the
 * current navigation and start the redirect in one step. `redirectTo` carries the requested
 * URL so that sign-in lands where the user was heading.
 */
export const authGuard: CanActivateFn = (route, state) => {
  const auth = inject(AuthService);
  const router = inject(Router);

  if (auth.isAuthenticated()) {
    return true;
  }

  return router.createUrlTree(['/login'], { queryParams: { redirectTo: state.url } });
};

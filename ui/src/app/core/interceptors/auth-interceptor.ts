import { HttpErrorResponse, HttpInterceptorFn, HttpRequest } from '@angular/common/http';
import { inject } from '@angular/core';
import { catchError, switchMap, throwError } from 'rxjs';

import { environment } from '../../../environments/environment';
import { AuthService } from '../services/auth-service';

/** Routes the contract marks `security: []`. Sending a bearer token to them is pointless. */
const PUBLIC_AUTH_ROUTES = ['/auth/login', '/auth/register', '/auth/refresh'];

/**
 * Attach the access token, and recover from a 401 once.
 *
 * Two rules are worth reading closely.
 *
 * The token goes only to the two configured platform origins. An interceptor that adds the
 * header to every outbound request will hand the session token to any third party the
 * application ever calls, including an image CDN, and that is how tokens leak.
 *
 * A 401 triggers one refresh attempt and one retry. If the refresh fails, the session is
 * over: clear it and send the user to the sign-in screen. Retrying without that limit gives
 * an infinite loop the moment the Auth service is down.
 */
export const authInterceptor: HttpInterceptorFn = (request, next) => {
  const auth = inject(AuthService);

  if (!isPlatformApi(request.url) || isPublicAuthRoute(request.url)) {
    return next(request);
  }

  return next(withBearerToken(request, auth.getToken())).pipe(
    catchError((error: unknown) => {
      if (!(error instanceof HttpErrorResponse) || error.status !== 401) {
        return throwError(() => error);
      }

      if (!auth.getRefreshToken()) {
        auth.logout();
        return throwError(() => error);
      }

      return auth.refresh().pipe(
        switchMap((tokens) => next(withBearerToken(request, tokens.accessToken))),
        catchError(() => {
          // The refresh token is expired, revoked or already consumed. Nothing left to try.
          auth.logout();
          return throwError(() => error);
        }),
      );
    }),
  );
};

function withBearerToken<T>(request: HttpRequest<T>, token: string | null): HttpRequest<T> {
  return token ? request.clone({ setHeaders: { Authorization: `Bearer ${token}` } }) : request;
}

function isPlatformApi(url: string): boolean {
  return url.startsWith(environment.tradeApiBaseUrl) || url.startsWith(environment.authApiBaseUrl);
}

function isPublicAuthRoute(url: string): boolean {
  return PUBLIC_AUTH_ROUTES.some((route) => url.includes(route));
}

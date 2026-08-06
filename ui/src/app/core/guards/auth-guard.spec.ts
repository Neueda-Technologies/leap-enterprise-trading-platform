import { TestBed } from '@angular/core/testing';
import {
  ActivatedRouteSnapshot,
  Router,
  RouterStateSnapshot,
  UrlTree,
  provideRouter,
} from '@angular/router';

import { AuthService } from '../services/auth-service';
import { authGuard } from './auth-guard';

describe('authGuard', () => {
  let authenticated: boolean;

  function run(url: string): boolean | UrlTree {
    return TestBed.runInInjectionContext(() =>
      authGuard({} as ActivatedRouteSnapshot, { url } as RouterStateSnapshot),
    ) as boolean | UrlTree;
  }

  beforeEach(() => {
    authenticated = false;

    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: AuthService, useValue: { isAuthenticated: () => authenticated } },
      ],
    });
  });

  it('allows the navigation when the session holds a usable token', () => {
    authenticated = true;
    expect(run('/dashboard')).toBe(true);
  });

  it('redirects to sign-in when there is no usable token', () => {
    const result = run('/dashboard');
    expect(result).toBeInstanceOf(UrlTree);
  });

  it('carries the requested URL so that sign-in lands where the user was heading', () => {
    const router = TestBed.inject(Router);
    const result = run('/orders/new') as UrlTree;

    expect(router.serializeUrl(result)).toBe('/login?redirectTo=%2Forders%2Fnew');
  });
});

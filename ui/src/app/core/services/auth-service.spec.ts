import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';

import { environment } from '../../../environments/environment';
import { makeAccessToken, makeExpiredAccessToken } from '../../../testing/token';
import { TokenResponse, UserResponse } from '../models/auth-api';
import { AuthService } from './auth-service';

const AUTH = environment.authApiBaseUrl;

const USER: UserResponse = {
  id: '8f14e45f-ceea-4c1b-9d3b-1a2b3c4d5e6f',
  username: 'priya.menon',
  accountId: 1,
  roles: ['CUSTOMER'],
};

function tokenResponse(accessToken = makeAccessToken(), refreshToken = 'refresh-1'): TokenResponse {
  return { accessToken, refreshToken, tokenType: 'Bearer', expiresIn: 900 };
}

describe('AuthService', () => {
  let service: AuthService;
  let http: HttpTestingController;
  let router: { navigate: ReturnType<typeof vi.fn> };

  beforeEach(() => {
    // The service reads storage while it is constructed, so clear it before injection.
    localStorage.clear();
    router = { navigate: vi.fn() };

    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: Router, useValue: router },
      ],
    });

    service = TestBed.inject(AuthService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  it('stores the token pair and the user after a successful sign-in', () => {
    let received: UserResponse | undefined;
    service.login({ username: 'priya.menon', password: 'correct horse battery staple' }).subscribe({
      next: (user) => (received = user),
    });

    const login = http.expectOne(`${AUTH}/auth/login`);
    expect(login.request.method).toBe('POST');
    expect(login.request.body).toEqual({
      username: 'priya.menon',
      password: 'correct horse battery staple',
    });
    login.flush(tokenResponse('access-token-1'));

    // The user is read back from the protected route, not from the token payload.
    const me = http.expectOne(`${AUTH}/auth/me`);
    expect(me.request.method).toBe('GET');
    me.flush(USER);

    expect(received).toEqual(USER);
    expect(service.getToken()).toBe('access-token-1');
    expect(service.getRefreshToken()).toBe('refresh-1');
    expect(service.currentUser()).toEqual(USER);
    expect(service.accountId()).toBe(1);
    expect(localStorage.getItem('etp.accessToken')).toBe('access-token-1');
  });

  it('is not authenticated when no token is held', () => {
    expect(service.isAuthenticated()).toBe(false);
  });

  it('is authenticated when the access token has not expired', () => {
    service.login({ username: 'priya.menon', password: 'x' }).subscribe();
    http.expectOne(`${AUTH}/auth/login`).flush(tokenResponse(makeAccessToken()));
    http.expectOne(`${AUTH}/auth/me`).flush(USER);

    expect(service.isAuthenticated()).toBe(true);
  });

  it('is not authenticated when the access token has expired', () => {
    service.login({ username: 'priya.menon', password: 'x' }).subscribe();
    http.expectOne(`${AUTH}/auth/login`).flush(tokenResponse(makeExpiredAccessToken()));
    http.expectOne(`${AUTH}/auth/me`).flush(USER);

    expect(service.isAuthenticated()).toBe(false);
  });

  it('is not authenticated when the token is not a readable JWT', () => {
    service.login({ username: 'priya.menon', password: 'x' }).subscribe();
    http.expectOne(`${AUTH}/auth/login`).flush(tokenResponse('not-a-jwt'));
    http.expectOne(`${AUTH}/auth/me`).flush(USER);

    expect(service.isAuthenticated()).toBe(false);
  });

  it('clears the session and returns to sign-in on logout', () => {
    service.login({ username: 'priya.menon', password: 'x' }).subscribe();
    http.expectOne(`${AUTH}/auth/login`).flush(tokenResponse());
    http.expectOne(`${AUTH}/auth/me`).flush(USER);

    service.logout();

    expect(service.getToken()).toBeNull();
    expect(service.getRefreshToken()).toBeNull();
    expect(service.currentUser()).toBeNull();
    expect(localStorage.getItem('etp.accessToken')).toBeNull();
    expect(router.navigate).toHaveBeenCalledWith(['/login']);
  });

  it('exchanges the refresh token for a new pair', () => {
    seedSession(service, http);

    service.refresh().subscribe();

    const refresh = http.expectOne(`${AUTH}/auth/refresh`);
    expect(refresh.request.method).toBe('POST');
    expect(refresh.request.body).toEqual({ refreshToken: 'refresh-1' });
    refresh.flush(tokenResponse('access-token-2', 'refresh-2'));

    expect(service.getToken()).toBe('access-token-2');
    expect(service.getRefreshToken()).toBe('refresh-2');
  });

  it('sends one request when several callers refresh at once', () => {
    seedSession(service, http);

    service.refresh().subscribe();
    service.refresh().subscribe();
    service.refresh().subscribe();

    // A second refresh presenting an already consumed token is treated as theft by the
    // Auth service and revokes the whole chain, so this must stay at one.
    http.expectOne(`${AUTH}/auth/refresh`).flush(tokenResponse('access-token-2', 'refresh-2'));
  });

  it('clears the session when the refresh is rejected', () => {
    seedSession(service, http);

    let failed = false;
    service.refresh().subscribe({ error: () => (failed = true) });
    http
      .expectOne(`${AUTH}/auth/refresh`)
      .flush(
        { errorCode: 'AUTH-401', message: 'Unauthorised' },
        { status: 401, statusText: 'Unauthorised' },
      );

    expect(failed).toBe(true);
    expect(service.getToken()).toBeNull();
    expect(service.isAuthenticated()).toBe(false);
  });

  it('fails the refresh without a request when no refresh token is held', () => {
    let failed = false;
    service.refresh().subscribe({ error: () => (failed = true) });

    expect(failed).toBe(true);
    http.expectNone(`${AUTH}/auth/refresh`);
  });

  it('fetches the account key once when the cache is empty', () => {
    let accountId: number | undefined;
    service.requireAccountId().subscribe((id) => (accountId = id));
    http.expectOne(`${AUTH}/auth/me`).flush(USER);
    expect(accountId).toBe(1);

    // Second call is served from the cached user.
    service.requireAccountId().subscribe((id) => (accountId = id));
    http.expectNone(`${AUTH}/auth/me`);
    expect(accountId).toBe(1);
  });
});

/** Sign in so that a refresh token is held. */
function seedSession(service: AuthService, http: HttpTestingController): void {
  service.login({ username: 'priya.menon', password: 'x' }).subscribe();
  http.expectOne(`${AUTH}/auth/login`).flush(tokenResponse('access-token-1', 'refresh-1'));
  http.expectOne(`${AUTH}/auth/me`).flush(USER);
}

import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';

import { environment } from '../../../environments/environment';
import { TokenResponse } from '../models/auth-api';
import { AuthService } from '../services/auth-service';
import { authInterceptor } from './auth-interceptor';

const TRADE = environment.tradeApiBaseUrl;
const AUTH = environment.authApiBaseUrl;

const UNAUTHORISED = { errorCode: 'AUTH-401', message: 'Unauthorised' };

function newTokens(): TokenResponse {
  return {
    accessToken: 'access-token-2',
    refreshToken: 'refresh-2',
    tokenType: 'Bearer',
    expiresIn: 900,
  };
}

describe('authInterceptor', () => {
  let http: HttpClient;
  let controller: HttpTestingController;
  let auth: {
    getToken: ReturnType<typeof vi.fn>;
    getRefreshToken: ReturnType<typeof vi.fn>;
    refresh: ReturnType<typeof vi.fn>;
    logout: ReturnType<typeof vi.fn>;
  };

  beforeEach(() => {
    auth = {
      getToken: vi.fn(() => 'access-token-1'),
      getRefreshToken: vi.fn(() => 'refresh-1'),
      refresh: vi.fn(() => of(newTokens())),
      logout: vi.fn(),
    };

    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([authInterceptor])),
        provideHttpClientTesting(),
        { provide: AuthService, useValue: auth },
      ],
    });

    http = TestBed.inject(HttpClient);
    controller = TestBed.inject(HttpTestingController);
  });

  afterEach(() => controller.verify());

  it('attaches the bearer token to a Trade REST API request', () => {
    http.get(`${TRADE}/api/v1/accounts/1`).subscribe();

    const request = controller.expectOne(`${TRADE}/api/v1/accounts/1`);
    expect(request.request.headers.get('Authorization')).toBe('Bearer access-token-1');
    request.flush({});
  });

  it('attaches the bearer token to the protected auth route', () => {
    http.get(`${AUTH}/auth/me`).subscribe();

    const request = controller.expectOne(`${AUTH}/auth/me`);
    expect(request.request.headers.get('Authorization')).toBe('Bearer access-token-1');
    request.flush({});
  });

  it('does not attach the token to sign-in or refresh', () => {
    http.post(`${AUTH}/auth/login`, {}).subscribe();
    const login = controller.expectOne(`${AUTH}/auth/login`);
    expect(login.request.headers.has('Authorization')).toBe(false);
    login.flush({});

    http.post(`${AUTH}/auth/refresh`, {}).subscribe();
    const refresh = controller.expectOne(`${AUTH}/auth/refresh`);
    expect(refresh.request.headers.has('Authorization')).toBe(false);
    refresh.flush({});
  });

  it('does not attach the token to a third-party origin', () => {
    // Sending the session token off-platform is how tokens leak.
    http.get('https://example.invalid/logo.png').subscribe();

    const request = controller.expectOne('https://example.invalid/logo.png');
    expect(request.request.headers.has('Authorization')).toBe(false);
    request.flush({});
  });

  it('refreshes once and retries the request after a 401', () => {
    let body: unknown;
    http.get(`${TRADE}/api/v1/accounts/1/orders`).subscribe((response) => (body = response));

    controller
      .expectOne(`${TRADE}/api/v1/accounts/1/orders`)
      .flush(UNAUTHORISED, { status: 401, statusText: 'Unauthorised' });

    expect(auth.refresh).toHaveBeenCalledTimes(1);

    const retry = controller.expectOne(`${TRADE}/api/v1/accounts/1/orders`);
    expect(retry.request.headers.get('Authorization')).toBe('Bearer access-token-2');
    retry.flush([{ orderId: 'ORD-1' }]);

    expect(body).toEqual([{ orderId: 'ORD-1' }]);
  });

  it('signs the user out when the refresh fails', () => {
    // AuthService.logout clears the session and navigates to /login. The redirect itself is
    // asserted in auth-service.spec.ts, where the Router is stubbed.
    auth.refresh = vi.fn(() => throwError(() => new Error('refresh rejected')));

    let status = 0;
    http.get(`${TRADE}/api/v1/accounts/1`).subscribe({ error: (error) => (status = error.status) });

    controller
      .expectOne(`${TRADE}/api/v1/accounts/1`)
      .flush(UNAUTHORISED, { status: 401, statusText: 'Unauthorised' });

    expect(auth.logout).toHaveBeenCalledTimes(1);
    expect(status).toBe(401);
  });

  it('signs the user out without refreshing when no refresh token is held', () => {
    auth.getRefreshToken = vi.fn(() => null);

    http.get(`${TRADE}/api/v1/accounts/1`).subscribe({ error: () => undefined });
    controller
      .expectOne(`${TRADE}/api/v1/accounts/1`)
      .flush(UNAUTHORISED, { status: 401, statusText: 'Unauthorised' });

    expect(auth.refresh).not.toHaveBeenCalled();
    expect(auth.logout).toHaveBeenCalledTimes(1);
  });

  it('passes other failures through untouched', () => {
    let status = 0;
    http
      .post(`${TRADE}/api/v1/orders`, {})
      .subscribe({ error: (error) => (status = error.status) });

    controller
      .expectOne(`${TRADE}/api/v1/orders`)
      .flush(
        { errorCode: 'ORD-409', message: 'Duplicate order' },
        { status: 409, statusText: 'Conflict' },
      );

    expect(auth.refresh).not.toHaveBeenCalled();
    expect(auth.logout).not.toHaveBeenCalled();
    expect(status).toBe(409);
  });
});

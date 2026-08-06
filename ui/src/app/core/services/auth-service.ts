import { HttpClient } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { Observable, finalize, map, of, shareReplay, switchMap, tap, throwError } from 'rxjs';

import { environment } from '../../../environments/environment';
import { decodeAccessToken, isExpired } from '../jwt';
import { LoginRequest, RefreshRequest, TokenResponse, UserResponse } from '../models/auth-api';

/**
 * Storage keys. Prefixed so that two applications served from the same origin during a
 * workshop do not read each other's session.
 */
const ACCESS_TOKEN_KEY = 'etp.accessToken';
const REFRESH_TOKEN_KEY = 'etp.refreshToken';
const USER_KEY = 'etp.user';

/**
 * Holds the session: the token pair, the authenticated user, and the refresh flow.
 *
 * Tokens live in `localStorage` so that a page reload does not sign the user out. That choice
 * has a cost: any script running on this origin can read them, so an XSS defect becomes a
 * stolen session. The production answer is an httpOnly, SameSite cookie set by the Auth
 * service, which the browser will not hand to JavaScript at all. The capstone uses
 * `localStorage` because the Auth service issues bearer tokens rather than cookies, and
 * because seeing the token in developer tools is part of what Sprint 8 teaches. Access tokens
 * live fifteen minutes, which limits the damage.
 */
@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly router = inject(Router);
  private readonly baseUrl = environment.authApiBaseUrl;

  private readonly accessToken = signal<string | null>(read(ACCESS_TOKEN_KEY));
  private readonly refreshTokenValue = signal<string | null>(read(REFRESH_TOKEN_KEY));

  /** The authenticated user, from `GET /auth/me`. Null before the first sign-in. */
  readonly currentUser = signal<UserResponse | null>(readUser());

  /** The numeric account key this session may address. Null when signed out. */
  readonly accountId = computed(() => this.currentUser()?.accountId ?? null);

  readonly username = computed(() => this.currentUser()?.username ?? null);

  /**
   * One refresh at a time. Without this, six requests that all get a 401 at once fire six
   * refreshes, five of which present a token the first one has already consumed, and the
   * Auth service treats a reused refresh token as theft and revokes the chain.
   */
  private refreshInFlight: Observable<TokenResponse> | null = null;

  /**
   * Exchange credentials for a token pair, then read the user back from `/auth/me`.
   *
   * The user is read from the server rather than from the token payload because the payload
   * is unverified in the browser. `/auth/me` is a protected route, so a successful call also
   * proves the token the API just issued actually works.
   */
  login(credentials: LoginRequest): Observable<UserResponse> {
    return this.http.post<TokenResponse>(`${this.baseUrl}/auth/login`, credentials).pipe(
      tap((tokens) => this.storeTokens(tokens)),
      switchMap(() => this.loadCurrentUser()),
    );
  }

  /** Clear the session and return to the sign-in screen. */
  logout(): void {
    this.clearSession();
    void this.router.navigate(['/login']);
  }

  /**
   * True when a usable access token is held.
   *
   * This is a client-side convenience that keeps the router from opening a screen that would
   * only fail. It is not a security control: every protected request is authorised by the API.
   */
  isAuthenticated(): boolean {
    return !isExpired(decodeAccessToken(this.accessToken()));
  }

  getToken(): string | null {
    return this.accessToken();
  }

  getRefreshToken(): string | null {
    return this.refreshTokenValue();
  }

  /**
   * Exchange the refresh token for a new pair. Concurrent callers share one request.
   *
   * A failure here means the refresh token is expired, revoked or already consumed. There is
   * no recovery from that other than signing in again, so the session is cleared.
   */
  refresh(): Observable<TokenResponse> {
    if (this.refreshInFlight) {
      return this.refreshInFlight;
    }

    const refreshToken = this.refreshTokenValue();
    if (!refreshToken) {
      return throwError(() => new Error('No refresh token held'));
    }

    const body: RefreshRequest = { refreshToken };
    this.refreshInFlight = this.http.post<TokenResponse>(`${this.baseUrl}/auth/refresh`, body).pipe(
      tap({
        next: (tokens) => this.storeTokens(tokens),
        error: () => this.clearSession(),
      }),
      finalize(() => (this.refreshInFlight = null)),
      shareReplay({ bufferSize: 1, refCount: false }),
    );

    return this.refreshInFlight;
  }

  /** Read the authenticated user from the Auth service and cache it. */
  loadCurrentUser(): Observable<UserResponse> {
    return this.http
      .get<UserResponse>(`${this.baseUrl}/auth/me`)
      .pipe(tap((user) => this.storeUser(user)));
  }

  /**
   * The account key to address, fetching it if a page reload emptied the cache.
   *
   * Every screen needs it, and no screen should have to know whether it has been loaded yet.
   */
  requireAccountId(): Observable<number> {
    const known = this.accountId();
    return known === null ? this.loadCurrentUser().pipe(map((user) => user.accountId)) : of(known);
  }

  private storeTokens(tokens: TokenResponse): void {
    this.accessToken.set(tokens.accessToken);
    this.refreshTokenValue.set(tokens.refreshToken);
    write(ACCESS_TOKEN_KEY, tokens.accessToken);
    write(REFRESH_TOKEN_KEY, tokens.refreshToken);
  }

  private storeUser(user: UserResponse): void {
    this.currentUser.set(user);
    write(USER_KEY, JSON.stringify(user));
  }

  private clearSession(): void {
    this.accessToken.set(null);
    this.refreshTokenValue.set(null);
    this.currentUser.set(null);
    remove(ACCESS_TOKEN_KEY);
    remove(REFRESH_TOKEN_KEY);
    remove(USER_KEY);
  }
}

/*
 * Storage access is wrapped because `localStorage` throws in a browser with site data
 * blocked, and an exception thrown while the service is being constructed takes down the
 * whole application.
 */

function read(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function write(key: string, value: string): void {
  try {
    localStorage.setItem(key, value);
  } catch {
    // Storage is unavailable. The session then lasts until the tab is reloaded.
  }
}

function remove(key: string): void {
  try {
    localStorage.removeItem(key);
  } catch {
    // Nothing to do: there is no session left to protect.
  }
}

function readUser(): UserResponse | null {
  const raw = read(USER_KEY);
  if (!raw) {
    return null;
  }
  try {
    return JSON.parse(raw) as UserResponse;
  } catch {
    return null;
  }
}

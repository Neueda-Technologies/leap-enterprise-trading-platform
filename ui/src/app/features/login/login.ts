import { Component, inject, signal } from '@angular/core';
import { NonNullableFormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';

import { toApiError } from '../../core/api-error';
import { AuthService } from '../../core/services/auth-service';

/**
 * Sign in against `POST /auth/login`.
 *
 * The Auth service returns the same `AUTH-401` body for an unknown username and for a wrong
 * password, so this screen must not try to be more helpful than that. Saying which half was
 * wrong turns the sign-in form into a user enumeration tool.
 */
@Component({
  selector: 'app-login',
  imports: [ReactiveFormsModule],
  templateUrl: './login.html',
  styleUrl: './login.css',
})
export class Login {
  private readonly formBuilder = inject(NonNullableFormBuilder);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);

  /** Field rules mirror `LoginRequest` in `auth-api.yaml`. */
  readonly form = this.formBuilder.group({
    username: ['', [Validators.required, Validators.maxLength(64)]],
    password: ['', [Validators.required, Validators.maxLength(128)]],
  });

  readonly submitting = signal(false);
  readonly error = signal<string | null>(null);

  submit(): void {
    this.error.set(null);

    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    this.submitting.set(true);
    this.auth.login(this.form.getRawValue()).subscribe({
      next: () => {
        this.submitting.set(false);
        void this.router.navigateByUrl(this.destination());
      },
      error: (failure: unknown) => {
        this.submitting.set(false);
        this.error.set(toApiError(failure).message);
      },
    });
  }

  /**
   * Where to go after signing in.
   *
   * `redirectTo` is set by `authGuard` and arrives in the URL, which means the user controls
   * it. Accept only a path on this origin. Following `//evil.example` or `https://…` from a
   * query parameter is an open redirect, and it is what makes a phishing link convincing.
   */
  private destination(): string {
    const requested = this.route.snapshot.queryParamMap.get('redirectTo');
    const isLocalPath = !!requested && requested.startsWith('/') && !requested.startsWith('//');
    return isLocalPath ? requested : '/dashboard';
  }
}

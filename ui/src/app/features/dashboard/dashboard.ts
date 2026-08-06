import { Component, inject, signal } from '@angular/core';
import { CurrencyPipe, DatePipe, DecimalPipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { forkJoin, switchMap } from 'rxjs';

import { toApiError } from '../../core/api-error';
import { AccountResponse, BalanceResponse, PositionResponse } from '../../core/models/trade-api';
import { AccountService } from '../../core/services/account-service';
import { AuthService } from '../../core/services/auth-service';

/**
 * The landing screen: who you are, what cash you hold, what you are holding, and where to go
 * next.
 *
 * The three account endpoints are fetched together with `forkJoin` rather than one after
 * another. They do not depend on each other, and three sequential round trips is three times
 * the latency for no reason.
 */
@Component({
  selector: 'app-dashboard',
  imports: [RouterLink, CurrencyPipe, DecimalPipe, DatePipe],
  templateUrl: './dashboard.html',
  styleUrl: './dashboard.css',
})
export class Dashboard {
  private readonly accounts = inject(AccountService);
  private readonly auth = inject(AuthService);

  readonly account = signal<AccountResponse | null>(null);
  readonly balance = signal<BalanceResponse | null>(null);
  readonly positions = signal<PositionResponse[]>([]);
  readonly loading = signal(true);
  readonly error = signal<string | null>(null);

  constructor() {
    this.load();
  }

  load(): void {
    this.loading.set(true);
    this.error.set(null);

    this.auth
      .requireAccountId()
      .pipe(
        switchMap((accountId) =>
          forkJoin({
            account: this.accounts.getAccount(accountId),
            balance: this.accounts.getBalance(accountId),
            positions: this.accounts.getPositions(accountId),
          }),
        ),
      )
      .subscribe({
        next: (result) => {
          this.account.set(result.account);
          this.balance.set(result.balance);
          this.positions.set(result.positions);
          this.loading.set(false);
        },
        error: (failure: unknown) => {
          this.error.set(toApiError(failure).message);
          this.loading.set(false);
        },
      });
  }

  logout(): void {
    this.auth.logout();
  }
}

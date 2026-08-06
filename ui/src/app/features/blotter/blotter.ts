import { DatePipe, DecimalPipe } from '@angular/common';
import { Component, DestroyRef, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { RouterLink } from '@angular/router';
import { switchMap } from 'rxjs';

import { toApiError } from '../../core/api-error';
import { OrderHistoryEntry, OrderStatus } from '../../core/models/trade-api';
import { AuthService } from '../../core/services/auth-service';
import { OrderService } from '../../core/services/order-service';

/**
 * The blotter: every order recorded against the account, newest first.
 *
 * Rejected and cancelled orders are shown. The order table is the audit trail, and hiding the
 * failures from the trader who caused them defeats the point of keeping one.
 */
@Component({
  selector: 'app-blotter',
  imports: [RouterLink, DatePipe, DecimalPipe],
  templateUrl: './blotter.html',
  styleUrl: './blotter.css',
})
export class Blotter {
  private readonly orders = inject(OrderService);
  private readonly auth = inject(AuthService);
  private readonly destroyRef = inject(DestroyRef);

  readonly entries = signal<OrderHistoryEntry[]>([]);
  readonly loading = signal(true);
  readonly error = signal<string | null>(null);

  /** Maps to the optional `status` query parameter on the history endpoint. */
  readonly statusFilter = signal<OrderStatus | ''>('');
  readonly statuses: OrderStatus[] = ['NEW', 'FILLED', 'REJECTED', 'CANCELLED'];

  constructor() {
    this.load();
  }

  load(): void {
    this.loading.set(true);
    this.error.set(null);

    const status = this.statusFilter();

    this.auth
      .requireAccountId()
      .pipe(
        switchMap((accountId) => this.orders.getOrders(accountId, status ? { status } : {})),
        takeUntilDestroyed(this.destroyRef),
      )
      .subscribe({
        next: (entries) => {
          this.entries.set(entries);
          this.loading.set(false);
        },
        error: (failure: unknown) => {
          this.error.set(toApiError(failure).message);
          this.loading.set(false);
        },
      });
  }

  onStatusChange(value: string): void {
    this.statusFilter.set(value as OrderStatus | '');
    this.load();
  }

  badgeClass(status: OrderStatus): string {
    return `badge badge-${status.toLowerCase()}`;
  }
}

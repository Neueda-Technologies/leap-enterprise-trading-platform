import { DecimalPipe } from '@angular/common';
import { Component, DestroyRef, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { NonNullableFormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { switchMap } from 'rxjs';

import { toApiError } from '../../core/api-error';
import {
  AccountResponse,
  OrderHistoryEntry,
  OrderResponse,
  OrderSide,
  PlaceOrderRequest,
} from '../../core/models/trade-api';
import { AccountService } from '../../core/services/account-service';
import { AuthService } from '../../core/services/auth-service';
import { OrderService } from '../../core/services/order-service';
import { greaterThanZero, maxDecimalPlaces, wholeNumber } from '../../core/validators';

/**
 * What the screen is doing right now.
 *
 * `pending` is the state that only exists because execution is asynchronous. From Sprint 7
 * the API answers `NEW` and the fill arrives later, so the ticket has to stay on screen and
 * keep looking rather than declaring an outcome it does not have.
 */
type Phase = 'idle' | 'submitting' | 'pending' | 'settled' | 'timedOut';

/**
 * Place one order.
 *
 * Three things here are worth reading before writing your own version.
 *
 * The account is read-only. The account this session may trade comes from the verified token,
 * and the API returns ACC-403 if the body disagrees with the `accountId` claim. Making it an
 * editable field would offer the user an action that can only fail.
 *
 * The idempotency key is generated once per order and kept if, and only if, the request never
 * reached the server. A key regenerated on every retry places duplicate orders; a key reused
 * after the server has answered returns ORD-409.
 *
 * A `NEW` response starts a poll of order history. It never re-posts the order.
 */
@Component({
  selector: 'app-order-ticket',
  imports: [ReactiveFormsModule, RouterLink, DecimalPipe],
  templateUrl: './order-ticket.html',
  styleUrl: './order-ticket.css',
})
export class OrderTicket {
  private readonly formBuilder = inject(NonNullableFormBuilder);
  private readonly orders = inject(OrderService);
  private readonly accounts = inject(AccountService);
  private readonly auth = inject(AuthService);
  private readonly destroyRef = inject(DestroyRef);

  /** Field rules mirror `PlaceOrderRequest` in `trade-api.yaml`, business rules 4 and 5. */
  readonly form = this.formBuilder.group({
    symbol: [
      '',
      [Validators.required, Validators.maxLength(20), Validators.pattern(/^[A-Za-z0-9.:_-]+$/)],
    ],
    side: ['BUY' as OrderSide, [Validators.required]],
    // The upper bound is the int32 ceiling the contract declares, not a business limit.
    quantity: [
      1,
      [Validators.required, greaterThanZero, wholeNumber, Validators.max(2_147_483_647)],
    ],
    price: [0.01, [Validators.required, greaterThanZero, maxDecimalPlaces(2)]],
  });

  readonly account = signal<AccountResponse | null>(null);
  readonly accountId = signal<number | null>(null);
  readonly phase = signal<Phase>('idle');
  readonly error = signal<string | null>(null);

  /** The API's answer to the POST. Its status may still be `NEW`. */
  readonly placed = signal<OrderResponse | null>(null);

  /** The same order as last seen in order history, once the poll has read it back. */
  readonly resolved = signal<OrderHistoryEntry | null>(null);

  /** The status to display: the polled one when there is one, otherwise the posted one. */
  readonly status = computed(() => this.resolved()?.status ?? this.placed()?.status ?? null);

  readonly busy = computed(() => this.phase() === 'submitting' || this.phase() === 'pending');

  /**
   * Held between attempts so that a retry after a dropped connection is the same order.
   * Cleared as soon as the server has answered, whatever the answer was.
   */
  private idempotencyKey: string | null = null;

  constructor() {
    this.auth
      .requireAccountId()
      .pipe(
        switchMap((accountId) => {
          this.accountId.set(accountId);
          return this.accounts.getAccount(accountId);
        }),
        takeUntilDestroyed(this.destroyRef),
      )
      .subscribe({
        next: (account) => this.account.set(account),
        error: (failure: unknown) => this.error.set(toApiError(failure).message),
      });
  }

  submit(): void {
    this.error.set(null);

    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    const accountId = this.accountId();
    if (accountId === null) {
      this.error.set('The account is still loading. Try again in a moment.');
      return;
    }

    this.idempotencyKey ??= crypto.randomUUID();

    const value = this.form.getRawValue();
    const request: PlaceOrderRequest = {
      accountId,
      symbol: value.symbol.trim().toUpperCase(),
      side: value.side,
      quantity: Number(value.quantity),
      price: Number(value.price),
      idempotencyKey: this.idempotencyKey,
    };

    this.phase.set('submitting');
    this.placed.set(null);
    this.resolved.set(null);

    this.orders
      .placeOrder(request)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (response) => {
          this.idempotencyKey = null;
          this.placed.set(response);

          if (response.status === 'NEW') {
            this.phase.set('pending');
            this.track(accountId, response.orderId);
          } else {
            // Sprint 6 behaviour: the API filled inside the request.
            this.phase.set('settled');
            this.reloadAccount(accountId);
          }
        },
        error: (failure: unknown) => {
          const apiError = toApiError(failure);
          // Status 0 means the request never got a response, so the same key must be reused.
          if (apiError.status !== 0) {
            this.idempotencyKey = null;
          }
          this.phase.set('idle');
          this.error.set(apiError.message);
        },
      });
  }

  /** Clear the ticket for the next order. Keeps the symbol and side, which are usually reused. */
  reset(): void {
    const { symbol, side } = this.form.getRawValue();
    this.form.reset({ symbol, side, quantity: 1, price: 0.01 });
    this.phase.set('idle');
    this.placed.set(null);
    this.resolved.set(null);
    this.error.set(null);
  }

  private track(accountId: number, orderId: string): void {
    this.orders
      .watchOrder(accountId, orderId)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (entry) => {
          if (entry) {
            this.resolved.set(entry);
          }
        },
        error: (failure: unknown) => {
          this.phase.set('timedOut');
          this.error.set(toApiError(failure).message);
        },
        complete: () => {
          const entry = this.resolved();
          this.phase.set(entry && entry.status !== 'NEW' ? 'settled' : 'timedOut');
          this.reloadAccount(accountId);
        },
      });
  }

  /** A fill moves cash, so the read-only header is stale the moment the order settles. */
  private reloadAccount(accountId: number): void {
    this.accounts
      .getAccount(accountId)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({ next: (account) => this.account.set(account) });
  }
}

import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, concatMap, map, take, takeWhile, timer } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  OrderHistoryEntry,
  OrderHistoryQuery,
  OrderResponse,
  PlaceOrderRequest,
} from '../models/trade-api';

/**
 * Order placement, cancellation and history.
 *
 * The interesting method is `watchOrder`. From Sprint 7 the API returns before the fill
 * happens, so a UI that renders the response status as the outcome will show `NEW` forever
 * and the participant will assume the executor is broken.
 */
@Injectable({ providedIn: 'root' })
export class OrderService {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = environment.tradeApiBaseUrl;

  /**
   * `POST /api/v1/orders`.
   *
   * Returns `NEW` from Sprint 7 onwards, or a terminal status in Sprint 6 where the API still
   * fills inside the request. Both are valid under the contract and the caller handles both.
   */
  placeOrder(request: PlaceOrderRequest): Observable<OrderResponse> {
    return this.http.post<OrderResponse>(`${this.baseUrl}/api/v1/orders`, request);
  }

  /** `DELETE /api/v1/orders/{id}`. The id is the UUID, without the `ORD-` display prefix. */
  cancelOrder(orderId: string): Observable<OrderResponse> {
    const id = orderId.startsWith('ORD-') ? orderId.slice(4) : orderId;
    return this.http.delete<OrderResponse>(`${this.baseUrl}/api/v1/orders/${id}`);
  }

  /** `GET /api/v1/accounts/{id}/orders`. Newest first, including rejected and cancelled orders. */
  getOrders(accountId: number, query: OrderHistoryQuery = {}): Observable<OrderHistoryEntry[]> {
    let params = new HttpParams();
    if (query.status) {
      params = params.set('status', query.status);
    }
    if (query.from) {
      params = params.set('from', query.from);
    }
    if (query.to) {
      params = params.set('to', query.to);
    }

    return this.http.get<OrderHistoryEntry[]>(
      `${this.baseUrl}/api/v1/accounts/${accountId}/orders`,
      { params },
    );
  }

  /**
   * Follow one order until the Trade Executor resolves it, or until the attempts run out.
   *
   * Poll order history, not `POST /api/v1/orders`. Re-posting with the same idempotency key
   * returns ORD-409, and re-posting with a new key places a second order. The contract says
   * this in as many words.
   *
   * Emits on every poll so that the caller can keep showing a working state, and completes on
   * the first terminal status. The final emission is still `NEW` when the attempts are
   * exhausted, which the caller reports as "still working" rather than as a failure: the order
   * is recorded, and the blotter will show the outcome.
   */
  watchOrder(accountId: number, orderId: string): Observable<OrderHistoryEntry | null> {
    return timer(environment.orderPollIntervalMs, environment.orderPollIntervalMs).pipe(
      take(environment.orderPollAttempts),
      concatMap(() => this.getOrders(accountId)),
      map((orders) => orders.find((order) => order.orderId === orderId) ?? null),
      takeWhile((entry) => entry === null || entry.status === 'NEW', true),
    );
  }
}

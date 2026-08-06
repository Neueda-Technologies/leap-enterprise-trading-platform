import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { AccountResponse, BalanceResponse, PositionResponse } from '../models/trade-api';

/**
 * The account endpoints of the Trade REST API.
 *
 * Balance and positions are separate calls because they answer separate questions and the
 * API returns them separately. Neither carries market value: valuing a position needs a live
 * quote, and that belongs to the Sprint 10 Portfolio and P&L extension.
 */
@Injectable({ providedIn: 'root' })
export class AccountService {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = `${environment.tradeApiBaseUrl}/api/v1/accounts`;

  /** `GET /api/v1/accounts/{id}`. Holder name, business identifier, cash and status. */
  getAccount(accountId: number): Observable<AccountResponse> {
    return this.http.get<AccountResponse>(`${this.baseUrl}/${accountId}`);
  }

  /** `GET /api/v1/accounts/{id}/balance`. Available cash only, with its currency and timestamp. */
  getBalance(accountId: number): Observable<BalanceResponse> {
    return this.http.get<BalanceResponse>(`${this.baseUrl}/${accountId}/balance`);
  }

  /** `GET /api/v1/accounts/{id}/positions`. Net held quantity and average cost. Zero rows are omitted. */
  getPositions(accountId: number): Observable<PositionResponse[]> {
    return this.http.get<PositionResponse[]>(`${this.baseUrl}/${accountId}/positions`);
  }
}

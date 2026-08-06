/*
 * Typed models for the Trade REST API, hand-written from `docs/contracts/trade-api.yaml`.
 *
 * Every name and every optionality here comes from the contract. When the contract changes,
 * change this file first and let the compiler find the call sites. See the README for the
 * `openapi-generator` command that produces the same interfaces mechanically.
 *
 * `accountId` means the numeric key `ACCOUNTS.id` everywhere except
 * `AccountResponse.accountId`, which is the string business identifier. The contract
 * documents that collision; this file reproduces it rather than inventing a nicer name,
 * because a field renamed here is a defect that only shows up at runtime.
 */

/** Direction of the order. */
export type OrderSide = 'BUY' | 'SELL';

/**
 * `NEW` is the working state, held from acceptance until the Trade Executor resolves it.
 * The other three are terminal. There is no partial-fill state.
 */
export type OrderStatus = 'NEW' | 'FILLED' | 'REJECTED' | 'CANCELLED';

/** Only an ACTIVE account may place or cancel orders. */
export type AccountStatus = 'ACTIVE' | 'SUSPENDED' | 'CLOSED';

/** The error catalogue served by the Trade REST API. Branch on this, never on the message. */
export type TradeErrorCode =
  'ACC-404' | 'ACC-403' | 'INS-404' | 'ORD-400' | 'ORD-409' | 'VAL-422' | 'AUTH-401';

export interface PlaceOrderRequest {
  /** The numeric account key. Must match the token's `accountId` claim or the API returns ACC-403. */
  accountId: number;
  /** Instrument symbol, 1 to 20 characters, matching `INSTRUMENTS.symbol`. */
  symbol: string;
  side: OrderSide;
  /** Whole units, greater than zero. Business rule 4. */
  quantity: number;
  /** Limit price per unit to two decimal places, greater than zero. Business rule 5. */
  price: number;
  /**
   * Client-generated unique request identifier. A reused key returns ORD-409, so it is not
   * a way to poll for status. Generate one per order, not one per session.
   */
  idempotencyKey: string;
}

export interface OrderResponse {
  /** Displayed with an `ORD-` prefix over the stored UUID. */
  orderId: string;
  status: OrderStatus;
  /** Human-readable outcome. For display only. Never branch on this string. */
  message: string;
  symbol: string;
  side: OrderSide;
  quantity: number;
  price: number;
}

export interface OrderHistoryEntry {
  orderId: string;
  accountId: number;
  symbol: string;
  side: OrderSide;
  quantity: number;
  /** The limit price submitted with the order. */
  price: number;
  /** The price the Trade Executor filled at. Null until the order is FILLED. */
  executedPrice?: number | null;
  status: OrderStatus;
  idempotencyKey?: string;
  createdOn: string;
}

export interface AccountResponse {
  /** The numeric account key. This is what every other endpoint calls `accountId`. */
  id: number;
  /** The string business identifier, `ACCOUNTS.account_id`, for example `ACC-000001`. */
  accountId: string;
  holderName: string;
  cashBalance: number;
  status: AccountStatus;
  /** Optimistic lock version. Increments on every write to the account row. */
  version: number;
  lastUpdated: string;
}

export interface BalanceResponse {
  accountId: number;
  cashBalance: number;
  /** ISO 4217 code. */
  currency: string;
  asOf: string;
}

export interface PositionResponse {
  accountId: number;
  symbol: string;
  /** Net held quantity. Never negative; short selling is out of scope. */
  quantity: number;
  /** Weighted average cost basis per unit. */
  averageCost: number;
}

/** Optional filters on `GET /api/v1/accounts/{id}/orders`. */
export interface OrderHistoryQuery {
  status?: OrderStatus;
  /** ISO instant. Include orders created on or after this time. */
  from?: string;
  /** ISO instant. Include orders created on or before this time. */
  to?: string;
}

/** The single error envelope. Both APIs use it, so the UI has one error handler. */
export interface ErrorResponse {
  errorCode: string;
  message: string;
}

/** An order in a terminal state will not change again. */
export function isTerminal(status: OrderStatus): boolean {
  return status !== 'NEW';
}

import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { NEVER, of } from 'rxjs';

import {
  AccountResponse,
  OrderHistoryEntry,
  OrderResponse,
  PlaceOrderRequest,
} from '../../core/models/trade-api';
import { AccountService } from '../../core/services/account-service';
import { AuthService } from '../../core/services/auth-service';
import { OrderService } from '../../core/services/order-service';
import { OrderTicket } from './order-ticket';

const ACCOUNT: AccountResponse = {
  id: 1,
  accountId: 'ACC-000001',
  holderName: 'Priya Menon',
  cashBalance: 24500.75,
  status: 'ACTIVE',
  version: 7,
  lastUpdated: '2026-09-28T09:14:22Z',
};

function accepted(status: OrderResponse['status'] = 'NEW'): OrderResponse {
  return {
    orderId: 'ORD-6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e',
    status,
    message: status === 'NEW' ? 'Order accepted' : 'Order executed',
    symbol: 'ACME',
    side: 'BUY',
    quantity: 100,
    price: 25.5,
  };
}

function filledEntry(): OrderHistoryEntry {
  return {
    orderId: 'ORD-6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e',
    accountId: 1,
    symbol: 'ACME',
    side: 'BUY',
    quantity: 100,
    price: 25.5,
    executedPrice: 25.48,
    status: 'FILLED',
    createdOn: '2026-09-28T09:14:22Z',
  };
}

describe('OrderTicket', () => {
  let fixture: ComponentFixture<OrderTicket>;
  let component: OrderTicket;
  let orders: {
    placeOrder: ReturnType<typeof vi.fn>;
    watchOrder: ReturnType<typeof vi.fn>;
  };

  /** Fill the form with a ticket the API would accept. */
  function validTicket(): void {
    component.form.setValue({ symbol: 'acme', side: 'BUY', quantity: 100, price: 25.5 });
  }

  beforeEach(async () => {
    orders = {
      placeOrder: vi.fn(() => of(accepted('NEW'))),
      watchOrder: vi.fn(() => NEVER),
    };

    await TestBed.configureTestingModule({
      imports: [OrderTicket],
      providers: [
        // The template carries routerLink, which needs a Router and an ActivatedRoute.
        provideRouter([]),
        { provide: OrderService, useValue: orders },
        { provide: AccountService, useValue: { getAccount: () => of(ACCOUNT) } },
        { provide: AuthService, useValue: { requireAccountId: () => of(1) } },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(OrderTicket);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('loads the account read-only, from the session rather than from a field', () => {
    expect(component.account()).toEqual(ACCOUNT);
    expect(component.accountId()).toBe(1);

    const host = fixture.nativeElement as HTMLElement;
    const field = host.querySelector<HTMLInputElement>('[data-testid="account-field"]');
    expect(field?.readOnly).toBe(true);
    expect(field?.value).toContain('Priya Menon');
  });

  describe('validation, mirroring business rules 4 and 5', () => {
    it('accepts a well-formed ticket', () => {
      validTicket();
      expect(component.form.valid).toBe(true);
    });

    it('rejects an empty symbol', () => {
      validTicket();
      component.form.controls.symbol.setValue('');
      expect(component.form.controls.symbol.hasError('required')).toBe(true);
    });

    it('rejects a symbol longer than the contract allows', () => {
      validTicket();
      component.form.controls.symbol.setValue('A'.repeat(21));
      expect(component.form.controls.symbol.hasError('maxlength')).toBe(true);
    });

    it('rejects a quantity of zero', () => {
      validTicket();
      component.form.controls.quantity.setValue(0);
      expect(component.form.controls.quantity.hasError('greaterThanZero')).toBe(true);
      expect(component.form.valid).toBe(false);
    });

    it('rejects a negative quantity', () => {
      validTicket();
      component.form.controls.quantity.setValue(-10);
      expect(component.form.controls.quantity.hasError('greaterThanZero')).toBe(true);
    });

    it('rejects a fractional quantity, because orders are in whole units', () => {
      validTicket();
      component.form.controls.quantity.setValue(1.5);
      expect(component.form.controls.quantity.hasError('wholeNumber')).toBe(true);
    });

    it('rejects a price of zero', () => {
      validTicket();
      component.form.controls.price.setValue(0);
      expect(component.form.controls.price.hasError('greaterThanZero')).toBe(true);
    });

    it('rejects a negative price', () => {
      validTicket();
      component.form.controls.price.setValue(-1);
      expect(component.form.controls.price.hasError('greaterThanZero')).toBe(true);
    });

    it('rejects a price carrying more than two decimal places', () => {
      validTicket();
      component.form.controls.price.setValue(25.555);
      expect(component.form.controls.price.hasError('maxDecimalPlaces')).toBe(true);
    });

    it('does not call the API while the form is invalid', () => {
      component.form.controls.quantity.setValue(0);
      component.submit();

      expect(orders.placeOrder).not.toHaveBeenCalled();
      expect(component.form.controls.quantity.touched).toBe(true);
    });
  });

  describe('submission', () => {
    it('posts the account key, the uppercased symbol and a fresh idempotency key', () => {
      validTicket();
      component.submit();

      expect(orders.placeOrder).toHaveBeenCalledTimes(1);
      const request = orders.placeOrder.mock.calls[0][0] as PlaceOrderRequest;
      expect(request.accountId).toBe(1);
      expect(request.symbol).toBe('ACME');
      expect(request.side).toBe('BUY');
      expect(request.quantity).toBe(100);
      expect(request.price).toBe(25.5);
      expect(request.idempotencyKey.length).toBeGreaterThanOrEqual(8);
    });

    it('holds a pending state and polls order history when the API answers NEW', () => {
      validTicket();
      component.submit();

      expect(component.phase()).toBe('pending');
      expect(component.status()).toBe('NEW');
      expect(orders.watchOrder).toHaveBeenCalledWith(1, 'ORD-6f2b1c2a-6a1e-4a4f-9c0d-2f7a1b3c4d5e');
    });

    it('shows the terminal status once the poll reads the fill back', () => {
      orders.watchOrder = vi.fn(() => of(filledEntry()));

      validTicket();
      component.submit();

      expect(component.status()).toBe('FILLED');
      expect(component.phase()).toBe('settled');
    });

    it('settles immediately when the API fills inside the request, as in Sprint 6', () => {
      orders.placeOrder = vi.fn(() => of(accepted('FILLED')));

      validTicket();
      component.submit();

      expect(component.phase()).toBe('settled');
      expect(component.status()).toBe('FILLED');
      expect(orders.watchOrder).not.toHaveBeenCalled();
    });

    it('gives every order its own idempotency key', () => {
      orders.watchOrder = vi.fn(() => of(filledEntry()));

      validTicket();
      component.submit();
      component.reset();
      validTicket();
      component.submit();

      const first = (orders.placeOrder.mock.calls[0][0] as PlaceOrderRequest).idempotencyKey;
      const second = (orders.placeOrder.mock.calls[1][0] as PlaceOrderRequest).idempotencyKey;
      expect(first).not.toBe(second);
    });
  });
});

import { AbstractControl, ValidationErrors, ValidatorFn } from '@angular/forms';

/*
 * Validators that mirror rules the Trade REST API enforces.
 *
 * The API is the authority. These exist so that a mistake is caught while the user is still
 * looking at the field, not after a round trip that returns VAL-422. Never remove the
 * server-side rule because the client has one: anything can post to the API.
 */

/** Business rule 4. Quantity is whole units, so 1.5 shares is not an order. */
export function wholeNumber(control: AbstractControl): ValidationErrors | null {
  const value = control.value;
  if (value === null || value === '') {
    return null;
  }
  return Number.isInteger(Number(value)) ? null : { wholeNumber: true };
}

/** Business rules 4 and 5. Quantity and price are both `exclusiveMinimum: 0`. */
export function greaterThanZero(control: AbstractControl): ValidationErrors | null {
  const value = control.value;
  if (value === null || value === '') {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? null : { greaterThanZero: true };
}

/**
 * Prices are `multipleOf: 0.01` in the contract, because money to more than two decimal
 * places is a rounding argument waiting to happen.
 */
export function maxDecimalPlaces(places: number): ValidatorFn {
  return (control: AbstractControl): ValidationErrors | null => {
    const value = control.value;
    if (value === null || value === '') {
      return null;
    }
    const decimals = String(value).split('.')[1];
    return !decimals || decimals.length <= places ? null : { maxDecimalPlaces: { places } };
  };
}

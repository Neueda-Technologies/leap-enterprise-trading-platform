# order-ticket

The form that places an order, and the one screen in the application where a mistake costs
a customer money.

Validate before you submit. Quantity is a whole number greater than zero, price is greater
than zero with at most two decimal places, symbol matches the shape the contract allows,
and the account is the one the session may address rather than a field the user can type
into. A form that posts a zero quantity to find out that the server rejects it has wasted a
round trip and taught the user nothing.

Client-side validation is not the enforcement. Business rules 1 to 8 live in the Trade REST
API and stay there. The form exists so that the common mistakes never reach the wire, and
the error rendering exists because the rest of them will.

The account is read-only on this screen. The token says which account this session may
trade, and an account field the user can edit is an authorisation decision moved into the
browser.

`POST /api/v1/orders` may answer `NEW`. That is not an error and not a bug. Read the brief
before deciding what the screen does next.

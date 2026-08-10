# auth

The four routes, and the guard that protects the one of them that needs it.

Single responsibility: turn HTTP into a call on `users` or `tokens`, and turn
the result back into the body the contract describes. The controller takes a
validated DTO, calls one service method and maps the answer. It does not hash,
it does not sign, it does not run a statement, and it does not decide what a
role may do.

The guard belongs here because it is transport: it reads the `Authorization`
header, hands the token to `tokens` for verification, and attaches the verified
identity to the request. It verifies the signature, the expiry and the algorithm
the token asks for, in that order, before any claim is read. A guard that
decodes the payload first has already trusted whatever the client sent.

Every failure that leaves this module on an authentication path is the same
answer: `AUTH-401`, one body, one status, whatever the cause. Registration
conflicts are `AUTH-409` and validation failures are `VAL-422`, and neither of
those describes a credential.

The request and response DTOs live here, with their validation decorators and
their OpenAPI decorators. The decorators are what the served document is
generated from, so a DTO with no annotations produces a document that says
nothing.

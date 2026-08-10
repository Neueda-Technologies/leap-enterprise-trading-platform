# common

The pieces every module uses and none of them owns: the error envelope, the
logger, and the decorator that hands a handler its verified identity.

Single responsibility: cross-cutting mechanics with no domain knowledge.

The error envelope is produced in one place. Every failure leaves this service
as `{"errorCode": ..., "message": ...}` and nothing else, because the Angular
application in Sprint 9 has one error handler for the whole platform. An
unhandled fault leaves as an envelope too, carrying no exception name, no stack
and no statement.

The logger is where the never-log-a-password rule stops being an intention. Log
through one logger that redacts by key name at any depth, so that a credential
nested inside an error object cannot pass through it. Redaction is not a
substitute for never passing a request body to a log call, and it is the net
underneath.

The current-user decorator reads identity from the verified request and from
nowhere else. A handler that takes a user identifier from a query parameter or
a header is OWASP A01, and the decorator exists so that no handler is tempted.

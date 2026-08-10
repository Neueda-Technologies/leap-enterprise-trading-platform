# tokens

Signing, verification and the refresh token lifecycle.

Single responsibility: everything that knows what a token is. Two kinds, and
they are opposites.

The access token is a signed JWT carrying the claims contract, and nothing else.
It is stateless so that every other service verifies a request with a signature
and no call back here, and the price of that is that it cannot be withdrawn.
Fifteen minutes is the size of the price. Pin the algorithm when you verify: a
verifier that trusts the `alg` header accepts a token that names `none`.

The refresh token is opaque, random, stored and revocable. Store a hash of it
rather than the value, so that read access to the store is not session takeover.

Rotation lives here. A refresh consumes the presented token and issues a new
pair, and the presented token is dead before the response is written. Make the
consumption conditional in the statement that performs it, in the way Sprint 6
made the account update conditional on the version: read, decide, then update is
a race against the second presentation you are trying to catch.

A consumed token presented again is the theft signal. It means either a client
repeated a request or somebody stole the token, and nothing here can tell which,
so treat it as theft and revoke every live token for that user.

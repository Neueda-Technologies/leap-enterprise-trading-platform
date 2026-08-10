# config

Loading the environment, validating it, and refusing to start when it is wrong.

Single responsibility: turn environment variables into one typed object the rest
of the service reads. No other module calls `process.env`, because a value read
in five places is a value defaulted differently in five places.

Validate at boot and fail loudly. A missing `JWT_SECRET` must stop the process,
not fall back to a literal: a service that quietly signs with a default secret
issues tokens anybody who has read the source can forge, and it does so
silently. Check the length too. A short HS256 secret is brute-forceable offline
from any token the attacker already holds.

Nothing in this directory holds a value. It holds names, defaults that are safe
to publish, and the rules that decide whether the process is allowed to start.

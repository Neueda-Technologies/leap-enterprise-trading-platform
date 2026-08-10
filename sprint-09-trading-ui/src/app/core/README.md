# core

Everything the whole application depends on and no single screen owns: the generated API
clients, the services that wrap them, the interceptor, the guards and the error-code
mapping.

One direction of dependency. `features/` imports from `core/`. Nothing in `core/` imports
from `features/`. A service that reaches into a screen is a service that cannot be reused by
the next screen, and it is the first thing a reviewer looks for.

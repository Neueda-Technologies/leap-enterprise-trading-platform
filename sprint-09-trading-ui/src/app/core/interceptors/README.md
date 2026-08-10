# interceptors

One functional interceptor, registered once in `withInterceptors`, and the only place in
this application that sets an `Authorization` header. No component and no service builds
that header for itself.

Two behaviours it has to get right, and the second is a security control rather than a
convenience.

The token goes on every call to the Trade REST API and to the protected auth route.

The token goes on nothing else. Not to the Fauxnance API, not to a CDN, not to a mapping or
analytics host, not to anything whose origin is not one of yours. Decide by comparing the
outgoing URL against the origins in `src/environments/`, not by excluding a list of hosts
you happen to have thought of.

The spec beside this file is a deliverable. It covers the attaching case and the
not-attaching case, and the harness looks for both by name.

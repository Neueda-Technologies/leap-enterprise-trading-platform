# services

The application's own services, sitting between the generated clients and the screens.

The generated client knows the contract and nothing else. It has no view of a session, no
view of which account this browser may address, and no opinion about what to do with a
`NEW` order. That is what a service here adds.

Expect at least a session service that owns the tokens and answers whether the user is
signed in, and one service per area of the Trade REST API. Signals over stored observables
where a screen needs to read state more than once.

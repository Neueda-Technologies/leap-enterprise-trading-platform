# login

The sign-in screen. The only route in the application that an unauthenticated visitor may
reach.

It posts the credentials to the Auth service, stores what comes back, and navigates to
where the user was going. The Auth service answers `AUTH-401` with the same body for an
unknown user and for a wrong password, on purpose, so this screen must not be more specific
than the service is. One message for every sign-in failure.

The harness drives this form. Give the username field, the password field and the submit
button a stable `data-testid`, or tell the harness what you used in `manifest.env`. A test
that finds a control by the text on it breaks the first time somebody rewrites the label.

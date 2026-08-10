# guards

Route guards. They keep a signed-out user off the authenticated screens and send them to the
sign-in route, carrying where they were going so that the application can return them there
after a successful sign-in.

A guard is a usability control, not a security control. The bundle is public and the routes
in it are readable by anyone. Every authorisation decision is taken by the Trade REST API,
which verifies the token signature on every call. Write the guard because a user who lands
on an empty dashboard has been told nothing, not because it protects data.

Redirect to a path on this origin only. A return address taken from a query parameter and
followed without checking it is an open redirect.

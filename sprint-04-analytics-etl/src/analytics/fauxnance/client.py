"""HTTP client for the Fauxnance API.

Responsibility: issue one request, return one parsed response envelope, and
decide what to do when the request does not come back cleanly. The retry
policy lives here rather than in the caller, because a quota response and a
dropped connection are the client's problem to absorb and the pipeline should
not be written twice, once for the happy path and once for the sad one.

Four failures are different and the code has to treat them differently:

- 429, the daily quota is exhausted. The response carries a `Retry-After`
  header giving the seconds until it resets at midnight UTC. Waiting that out
  inside a batch run is rarely the right answer.
- another 4xx, for example 401 for a bad key or 404 for a symbol Fauxnance
  does not serve. Retrying repeats the same mistake at the same cost.
- a network failure or a timeout, where nothing reached the service. This is
  the one worth retrying, with a backoff so a struggling service is not made
  worse by your client.
- a 200 whose body is not the shape you expected. This is not an HTTP problem
  at all, and it belongs to the transform rather than here.

Take a `requests.Session` and a sleep function as arguments rather than
reaching for the module-level ones. A test that has to wait four real seconds
to prove a backoff works is a test that gets deleted in week 9.
"""

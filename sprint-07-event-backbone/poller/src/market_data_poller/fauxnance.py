"""The Fauxnance client: one batch call, and what to do when it fails.

Single responsibility: given a group of symbols, return the quotes Fauxnance
served for them. It publishes nothing and knows nothing about Kafka.

The call is `GET /quotes?symbols=A,B,C`, at most 25 symbols, and it costs one
request against the quota whatever the symbol count. The key goes in the
`X-Api-Key` header and is read from configuration, never from a literal here.

Three failure shapes, and they are not the same failure.

One symbol in the batch comes back as an error entry, or with no price. The
other symbols in the same response are fine. Log the symbol, count it, and
return the rest. Publishing a null price breaks the arithmetic of every
consumer downstream.

The whole call fails with a timeout or a connection error. It will probably
succeed later. Retry with a backoff that grows, up to a small bounded number of
attempts, and remember that every attempt costs a request.

The call returns 429. The quota is spent. It will not succeed later, because
the counter resets at midnight UTC rather than inside a retry window. Do not
retry it. Say so in the log and point at `GET /usage`.

Structure this module so that the HTTP layer is passed in rather than imported
and used directly. A test that has to reach Fauxnance to run is a test that
fails on a train, gets skipped by the third person who sees it fail, and spends
quota every time it does run.
"""

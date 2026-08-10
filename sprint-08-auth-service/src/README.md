# src

The auth service: the only component in the platform that ever sees a
credential, and the only one that issues a token.

The process entry point and the root module belong here, at the top, not inside
a feature directory. Everything global to the service is configured in one
place, so that a reviewer can answer "is validation on, and does it reject
unknown fields" without reading every controller: the validation pipe, the
exception filter that produces the platform error envelope, the logger, CORS
and the OpenAPI document.

One directory per module below. Dependencies run one way:

```
auth  ->  users, tokens
users ->  database
tokens -> database
common, config      used by all of them, depending on none of them
```

Nothing depends on `auth`. A cycle in that graph means a module has taken on a
second responsibility, and the usual sign of it is a repository that has started
throwing an HTTP status.

Reorganise this tree if your design says something else. Tell the harness what
you chose in `manifest.env`.

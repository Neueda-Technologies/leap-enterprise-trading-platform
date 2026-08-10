# errors

The mapping from an error code in the contracts to the sentence a trader reads.

Both contracts return the same envelope, `{ "errorCode": ..., "message": ... }`, so one
mapping covers the whole platform. Branch on `errorCode`. Never branch on `message`, and
never show the server's `message` as the user-facing text: it is written for a developer
reading a log, and it changes without notice.

Every code in the two catalogues needs a rendering here. The harness reads the codes out of
`contracts/trade-api.yaml` and `contracts/auth-api.yaml` and fails, naming the codes, when
one of them appears nowhere in this file.

Two failures are not in either catalogue and still have to be handled. A response the
browser never received, which arrives as status 0 and is usually a service that is not
running or a CORS rule that does not allow your origin. And a code you have never seen,
which needs a fallback sentence rather than a blank panel.

`manifest.env` names this file under `ERROR_MAPPING_FILE`. Put the mapping somewhere else,
or split it in two, and correct the manifest.

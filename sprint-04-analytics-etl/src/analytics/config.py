"""Configuration read from the environment, in one place.

Responsibility: turn environment variables into the handful of values the rest
of the package needs, and fail loudly when one is missing. The key comes from
`FAUXNANCE_API_KEY` and the base URL from `FAUXNANCE_BASE_URL`, both defined in
the repository root `.env.example`. Copy that file to `.env`, which is
git-ignored, and let `python-dotenv` load it.

Nothing outside this module reads `os.environ` for Fauxnance settings, so
there is exactly one place to look when a key is wrong and exactly one place a
key could leak from.

A missing key is a configuration error, not a runtime surprise. Raising here,
before the first request, is cheaper than discovering it as a 401 halfway
through a batch.
"""

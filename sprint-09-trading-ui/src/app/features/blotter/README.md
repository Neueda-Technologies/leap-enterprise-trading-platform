# blotter

Order history for the account: every order, newest first, rejections included.

A blotter that hides rejected orders is worse than no blotter. The rejection is the record
that the desk tried and was refused, and it is the first thing anyone looks for when a
customer rings up.

Four statuses, each with its own badge: `NEW`, `FILLED`, `REJECTED` and `CANCELLED`. The
badge carries the word as well as the colour.

An order at `NEW` is a working order, not a stalled one, and the screen has to say which of
those it is showing. Decide how the row stops being stale, and be able to defend the
interval you chose.

An account with no orders gets an empty state that says so. A blank table looks like a
failed request.

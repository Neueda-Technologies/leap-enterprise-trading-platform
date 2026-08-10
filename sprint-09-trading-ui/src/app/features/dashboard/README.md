# dashboard

The screen a signed-in user lands on: who they are, what cash they hold and what positions
are open.

Three reads against the Trade REST API, and they are independent of each other, so run them
together rather than in a chain. One slow call should not hold up the two that have already
answered.

Holdings are not valued here. A market value needs a live quote, this application never
calls the market-data API, and the Trade REST API does not price a position. Show the
quantity and the average cost the contract gives you.

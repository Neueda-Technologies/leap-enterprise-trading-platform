# Seed data

Four data files, extracted from the brokerage's existing books and handed to
you as they came out. They are plain CSV, comma separated, with a header row
and no quoted fields. Loading them into the schema you design is part of the
Sprint 3 deliverable, and your apply command has to do it unattended.

These files are the fixture set the rest of the programme runs on. Sprint 4
analyses them, Sprint 6 tests against them, and Sprint 7 prices them against
live quotes. Every symbol below is one the Fauxnance API serves, so quotes
resolve later without a second pass over your fixtures.

The column names here are business names. They are not a suggestion about what
your columns should be called, how many tables the data belongs in, or which
values belong together. Working that out is the exercise. Two files carry
values that identify the same customer, and deciding what that means in your
model is the first decision you will argue about.

Add rows if you want more to work with. Do not remove any, and do not rename a
symbol: later sprints and the check harness both expect what is here.

## `instrument-reference.csv`

Everything the firm allows, or once allowed, its customers to trade. Nine rows.

| Column | Meaning |
|---|---|
| `symbol` | The identifier the market-data API uses for this instrument. Externally assigned, stable, and the value carried on every order. |
| `instrument_name` | The name shown to a customer on a statement or a ticket. |
| `asset_category` | What kind of thing it is: a share, an exchange traded fund, a currency pair, a crypto pair. |
| `quote_currency` | The currency the market quotes this instrument in. |
| `open_for_trading` | Whether a new order in it is allowed today. `SATYAM.BO` is `false`: it stopped trading after a merger, it is still referenced by an order placed in May and by a holding somebody still owns, and it is not going away. |

Four Indian names, two US names, one currency pair and one crypto pair. The
mixture is deliberate: Sprint 4 breaks trading down by asset category, and a
file with nothing but shares gives that report one bar.

## `customer-accounts.csv`

The customers who trade through the platform. Six rows.

| Column | Meaning |
|---|---|
| `client_reference` | The account reference a customer quotes on a call and reads on a statement. It is the only identifier the firm has ever shown anyone outside the building. |
| `account_holder` | The name of the person who holds the account. |
| `cash_available` | Cash the account can spend, exact to two decimal places. |
| `state` | Whether the account trades. `ACTIVE` trades. `SUSPENDED` is frozen by compliance and reversible. `CLOSED` is finished and never trades again. |

`ETP-2203` holds barely enough cash to buy anything, which is how Sprint 6
reaches its insufficient-funds path. `ETP-2205` and `ETP-2206` are the frozen
and the finished account, and neither has ever placed an order, because an
account that traded after losing `ACTIVE` status would be a defect rather than
a fixture.

## `order-history.csv`

Every order these customers have placed, in whatever state it ended in.
Eighteen rows, spread across four months.

| Column | Meaning |
|---|---|
| `order_reference` | The firm's own identifier for this order. Unique for all time, and the value quoted in a complaint or an audit. |
| `client_request_id` | The identifier the customer's app generated for the request that placed the order. A retry of the same tap carries the same value, and the firm has to recognise it as the same instruction rather than a second one. |
| `client_reference` | The account the order was placed against. |
| `symbol` | The instrument being bought or sold. |
| `direction` | `BUY` or `SELL`. |
| `units` | How many units the customer asked for. Whole units only. |
| `unit_price` | For an order in the `FILLED` state, the price each unit was actually traded at. For every other state, the price the customer asked for. |
| `state` | `NEW` is still working. `FILLED`, `REJECTED` and `CANCELLED` are final. Nothing moves out of a final state, and there is no half-filled order. |
| `placed_at` | When the firm received the instruction. |

Rejected orders are in the file because they are kept. A customer refused
three times in a fortnight is a compliance question, and the answer has to be
in the database rather than in a log that rolled over.

The four months of `placed_at` values matter more than they look. The nightly
extract in Sprint 7 pulls everything created since it last ran, and a fixture
set stamped with one instant returns either all of it or none of it.

## `current-holdings.csv`

What each account owns right now. Seven rows.

| Column | Meaning |
|---|---|
| `client_reference` | The account holding the instrument. |
| `symbol` | The instrument held. |
| `units_held` | Net units currently owned. Never negative: short selling is out of scope. |
| `average_price_paid` | Weighted average price paid per unit for the units still held. |

This file is derived from the one before it. Every row here is the net result
of the `FILLED` orders for that account and instrument, with a sale reducing
the units held and leaving the average price alone. Reconcile the two after
you load them. If you can write the query that rebuilds this file from
`order-history.csv` and get the same numbers, you have understood what a
holding is, and you have written most of a check that Sprint 7 will want.

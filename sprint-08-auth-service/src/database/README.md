# database

The connection to the store, and how the credential tables come into existence.

Single responsibility: hand a pool or a client to the repositories above, and
apply the schema this service owns. Nothing here knows what a user is.

The operational tables, accounts, instruments, orders and positions, are owned
by the Sprint 3 schema and created by the shared init scripts. The credential
tables are owned by this service, so their DDL ships with this service. Two
teams editing one init script is how migrations start conflicting.

Put them in their own schema. The Trade REST API's role is then granted nothing
on the users table, and an injection defect in the trading path cannot read a
password hash. That separation is a line in your security review, so make it a
real one.

Decide how the schema is applied and write the decision down. Applying it at
boot needs the service's role to hold DDL rights, which a least-privilege
deployment role does not have. Applying it from the infrastructure keeps those
rights out of the service and adds a step a teammate has to know about. Both are
defensible, and shipping something that only works if you run it by hand is not.

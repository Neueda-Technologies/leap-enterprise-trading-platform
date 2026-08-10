# users

Registration, credential verification, password hashing and the credential
store.

Single responsibility: everything that knows what a password is. This is the
only module in the platform that handles one, and the only one that reads the
table it is stored in. Hashing lives behind one provider so that the algorithm
and its cost factors are changed in one file and tested in one file.

Three rules this module owns.

A plaintext password never leaves this module and never reaches the repository.
The repository stores and reads a hash, and a test that asserts the value passed
to the repository is not the value passed to the service is worth writing.

An unknown username costs the same as a wrong password. The lookup missing is
not a reason to return early: verify the supplied password against a fixed dummy
hash of the same algorithm and the same parameters, discard the result, and
answer exactly as a wrong password answers.

A role in a request body on the public registration route is ignored. Accepting
a self-declared `ADMIN` is privilege escalation with no defect required.

Statements are parameterised. Every value that reaches one arrives from outside
the service, and this table is the one worth stealing.

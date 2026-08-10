"""Transform: raw envelopes in, a clean tabular series out.

Responsibility: everything between the response and the store. Parsing the
envelope, typing the columns, handling the rows that are wrong, and deriving
whatever your claims need from a candle.

This module takes data and returns data. It opens no socket, reads no
environment variable and writes to no database, which is what makes it the
part of the pipeline that is cheap to test and therefore the part the
acceptance criteria insist is tested. Keep it that way. A transform that
fetches its own input when a row is missing cannot be run against a fixture.

Decide in advance what a bad row is and what happens to it, because the
Fauxnance data has bad rows and so will every source after it. A missing
close, a high below a low, a non-numeric price, a duplicated trading day, a
volume of null on a real trading day. Silently dropping them is a decision.
Silently keeping them is also a decision, and it is the one that puts a wrong
number in front of a reader who cannot check it. Write down which you chose.
"""

"""The run: extract, then transform, then load, in that order and once.

Responsibility: wiring, and only wiring. This is the module that knows the
symbols in scope, the date range, and which store to write to. The three steps
know none of that about each other.

Keep the wiring thin enough that it needs no tests of its own. If a reviewer
has to read this module to understand what your transform does, the logic has
drifted into the wrong place.

Give the run an entry point that a teammate can invoke without reading the
source. A `[project.scripts]` entry in `pyproject.toml` or a `__main__` block
both work; say in the sprint README which you chose and how to run it.
"""

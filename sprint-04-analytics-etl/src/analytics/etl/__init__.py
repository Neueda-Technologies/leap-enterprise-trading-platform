"""The pipeline: extract, transform, load, in three separable modules.

The split is not decoration. Extract is the only part that needs a key and a
network. Transform is the only part with interesting logic, and keeping it
free of both means it can be tested against a fixture in milliseconds. Load is
the only part that writes. When one of the three breaks, that division tells
you which third to look in.
"""

"""Runs the reference validator (worlds_src/vertebre/gen/validate.py) on any copy of the world.
usage: py_validate.py <repo root> <world dir>   -> prints one problem per line, exit 0 always."""
import os
import sys

root, world = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(root, "worlds_src", "vertebre", "gen"))
import common  # noqa: E402

common.OUT = world
common.CONTENT = os.path.join(world, "Content")
import validate  # noqa: E402

validate.OUT = common.OUT
validate.CONTENT = common.CONTENT
validate.main()
for p in validate.problems:
    print("PROBLEM", p)

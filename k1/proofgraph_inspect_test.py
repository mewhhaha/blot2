"""Guard the private validator's per-root state shape; not a K1 certificate."""
from pathlib import Path
import re

source = (Path(__file__).parent / "proofgraph_validate.goose").read_text()
assert "no_strict_cycle(expected[..ne],p.count,i+1,j.meter)" in source
assert "eq_min(expected[..ne],p.count,i+1,j.meter)" in source
assert "var seen:bool[16]" in source  # one term/strictness state set
assert "var seen:bool[8]" in source   # one explicit-Eq component
assert not re.search(r"\bbool\s*\[\s*(?:64|128)\s*\]", source), "pairwise bool table reintroduced"
print("proof validator uses bounded per-root visit sets; no pairwise bool table")

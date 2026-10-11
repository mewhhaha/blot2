# Symbolic optimizer body reuse (029)

Optimizer keys contain a normalized local-body fingerprint and compilation tier.
The source function ordinal is an owned result locator, outside the key.
Fingerprints select candidates; exact input proofs authorize reuse. Function,
import, signature and global references have separate relocation namespaces.

The graph proof compares machine types, instructions, checked parameter roles,
allocation ownership annotations and completed lifetime summaries. It follows
calls and explicitly tagged function-table constants through recursive cycles.
Imports retain their module/name and signature; globals retain scalar type,
initial bits and mutability. Named arena helpers must keep their runtime role
and prove their complete input graph, including helpers introduced by
optimization.

Mappings are bijective within each namespace. A split or merged target declines
the candidate. Local equality permits index changes; all other immediates remain
exact. Public function identities remain separate. This does not enable physical
code sharing or change the existing optional machine-body sharing policy.

One shared budget bounds a matcher to 1,000,000 proof steps, 64 candidates per
body and 4,096 mappings per candidate. Clearing a failed candidate does not
reset fuel. Exhaustion conservatively resumes ordinary optimization. The
positional shortcut first settles transitive input facts, then checks every
output reference; unchanged ordinals alone grant no permission to reuse.

Relocation clones the old optimized output before rewriting direct calls,
imports, signatures, globals and table references. Failed proofs and allocation
failures release candidate copies. Retained inputs and outputs remain immutable.
The table-reference flag fits existing instruction padding: instructions remain
eight bytes. Constant-folding passes treat tagged table indices as symbolic
references rather than numeric allocation sizes or offsets. Artifact replay
preserves the tag.

Portable optimizer captures use schema `blot-optimizer-capture-v3`. They own
import names and complete global facts, parameter roles and ownership
annotations. Decode checks references, annotation counts and table-reference
opcode/target validity before publication. Older schemas decline through the
ordinary artifact key check. Loading supplies candidates and still requires the
exact matcher.

## Focused verification

Zig 0.17.0, isolated incoming 043/050 source, followed by integration with 037:

```sh
zig build test -Doptimize=safe -Dllvm=false \
  -Dtest-filter=symbolic -Dtest-filter="portable optimizer" \
  -Dtest-filter="optimized bod" -Dtest-filter="unchanged callers" --summary all
```

The final focused run passes 39 laws: compilation three seconds, execution seven
seconds. Laws cover insertion, removal and reordering of unrelated resources;
recursive calls; imports, signatures, globals and indirect table targets;
transitive lifetime/host/global changes; introduced cleanup helpers at unchanged
ordinals; checked-role changes; conflicting maps; exhaustion; separate public
identities; and exact fresh/retained Wasm bytes. Full allocation-failure sweeps
cover relocation and portable captures. A portable import/table fixture survives
destruction of both its producing module and encoded bytes before shifted-index
reuse. Tests compare retained output instructions after failed candidates.

Root owns the required full compiler/analyzer gate for the combined 029/037
integration. Completion and its final source/binary pins are recorded after that
gate; the isolated focused pass is not the full qualification.

## Measurement pins and limits

The initial release comparison used ordinary compiler
`272f028932b0cc563049fe7e5f6f51139304f0ae4cf7213351fd55f5f5f7a127` and candidate
`235da98810ce5e9a13228017e5684cfaf1209727cae922ab712d5da8a7367ff7`. This
candidate precedes the final stricter signature-map and positional proofs. Its
exact patch/source digests are retained in ignored
`build/bench/symbolic-body-reuse/measured.patch` and `measured-pins.json`. These
measurements describe that pin, not the later integrated implementation.

Seven alternating release pairs over 13 public examples produce 182 rows with
identical Wasm, diagnostics and old semantic counters. Requested/peak allocation
deltas are zero and teardown live bytes are zero. CPU median ratios span
0.981–1.048; ECS is 1.037. Seven pairs over four synthetic workloads preserve
fresh/retained Wasm and report no unexpected problems. Process CPU accounting is
coarse at these sizes, often 10 ms; no overall compiler speedup is claimed.

Reproduction uses the ignored `build/bench/resolved-bodies/compare_release.py`
and `deno task bench:compile --workload synthetic --runs 7`, with CPU 7 affinity
and `BLOT_CACHE_DIR=""`. Distributions, logs and binary/harness pins live under
`build/bench/symbolic-body-reuse/public/` and `synthetic/`.

The intended improvement is optimizer reuse after incidental resource movement,
which native counters prove directly. Changed semantic targets, uncertain maps,
incomplete captures and exhausted proofs continue to decline. No stable semantic
identity is inferred from a fingerprint alone.

# Bounded private scalar callback checkpoint

Task 047 remains open. This extends the private-child tree
`f67f836cd1d4ec4a457bbdc3e70a06756f79321a`; strict zip and windows retain
ordinary state. The parent owns the combined compiler gate and integration.

An exact symbolic table word in a selected private closure may expose a checked
scalar consumer. The target signature/result, owning context and parameter roles
must match. Admission allows at most 96 code instructions, four parameters and
64 parameter/local slots. Internal blocks, conditional branches, scalar
arithmetic and scalar field reads execute at the original call position. Every
cloned local starts at Wasm's typed zero on each call; loop activations never
inherit an earlier call's local value. All branches must remain inside the
copied body. Calls, loops, memory writes, globals, host effects, source root
scopes, unknown roles and public entries decline. The existing tiny direct
projection-wrapper admission remains available.

This is enabled only by the existing private table-target proof. It does not
scan arbitrary direct callees. Snapshot initialization, exact offsets and escape
proofs still govern subsequent field replacement. Caller and target inputs are
immutable. The complete captured call graph already contains the callee inputs;
portable optimizer meaning advances to v21.

LLVM/Fast binary SHA256:
`338eea709a2e9ecfabfbc64d483a80cbe49b580d630ac319a270a3d11cd04945`. Compiler
identity: `1248c8786b60469da226d08d0e3b8c10e02b42d1ddca6489147b8a618ebe74ca`.
Exact source, artifact pins and raw reports are in
`/var/tmp/blot2-adapter-cost-047/build/bench/adapter-cost/pins.json`. Zig 0.17.0
is used throughout. Screening/rejected and diagnostic-only artifacts remain
alongside the accepted pin; they are not release qualification.

At 4,096 rows, ordinary modules use 20 warmups and 31 alternating CPU 7 pairs
with 16 invocations per sample. Profiling copies only measure counters; their
CPU is not compared. Final medians against the frozen private-child compiler:

| Adapter    | Allocations     | Requested payload | Root stores      | CPU ratio |
| ---------- | --------------- | ----------------- | ---------------- | --------- |
| enumerate  | 8192→0          | 49152→0           | 40963→0          | .0435     |
| zip        | 4096→0          | 24576→0           | 20483→0          | .0369     |
| zip_strict | 49158→45062     | 376880→360496     | 28678→20486      | .9722     |
| windows    | 81894 unchanged | 1277540 unchanged | 143315 unchanged | .9985     |

Range/map/filter/take/pipeline retain zero allocations; take_while retains its
two captured-predicate creation objects. Their CPU controls span 0.9885–1.0054.
All managed roots/leases are zero after calls and reset; the journal retains its
existing 4,096-byte page. Guest committed memory remains 128 KiB on both sides.
Saved cursors, conditional callbacks, dynamic reference pairs and F32 callback
order are executed. Edit/revert and restored checkpoints match fresh results in
optimized and development tiers, including changed consumer bodies.

All 62 U32/F32 record/tuple packed-width outputs are byte-for-byte equal to the
private-child baseline. All 124 fold/cursor allocation/answer comparisons are
exactly equal. This preserves the parent's prior boxed all-width qualification.
Legacy packed counter fixtures do not expose journal counters: those are null,
and their live/peak counters are cumulative; they grant no live-memory claim.

Focused native laws pass 27/27, including the new ten-case OOM/boundary law. Two
corrected rejection fixtures rerun 16/16; 36 guests/budget checks and 366
analyzed files/zero findings pass. An initial retained-test U32 oracle produced
JavaScript negative zero for count 0; normalized U32 expectation fixes that
fixture, and the complete focused guest/budget group passes afterward.

Seven retained synthetic pairs give population 25.130→24.438 ms, edit
8.651→8.610 ms, revert 7.756→7.682 ms and no-op 0.195→0.191 ms. Source fuel and
per-compiler fresh oracles are preserved; no-op work remains zero. Seven public
example pairs retain all 13 machine outputs and source fuel, with CPU ratios
0.9625–.9857. Normalized uncached CLI runs retain identical requested
allocation/peak/count for all 13 examples; the adapter synthetic requests
614,220 fewer bytes and 133 fewer allocations, with unchanged peak and zero
teardown. These are controls, not a general compiler speedup claim. Earlier
private-child cold cost and the parent's captured 93-unit assembly regression
remain recorded. The next cost hill is identifying why that retained workflow
reoptimizes every body.

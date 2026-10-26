# Structural compiler work and bounded release inlining

This follow-up implements the next two steps from the parity investigation:
reduce structural frontend/validator work, then add the existing bounded release
inlining policy. Syntax, source admission, ABI and shared generic bodies remain
unchanged. The implementation and measurements are on `rewrite/goose-k1`.

## Mechanisms

The validator's attempt context now borrows its immutable Core view. Previously,
passing a context also copied the large inventory of table slices. This is a
representation change, not a shortcut through validation: 54 before/after
admissions (accepted and hostile inputs across three modes) have identical
outcomes, diagnostics, canonical digests and exact validation/proof work counts.
Each validation attempt still owns separate budgets and scratch.

Proof contradiction search now uses iterative Tarjan SCCs over forward edges.
It removes reverse adjacency and the second graph traversal. The first active
strict-edge root, bounded BFS certificate, evidence order and direct contradiction
shortcut are preserved. At 8/10/16 guards, measured completion proof visits fall
from 4,179/6,407/16,147 to 3,551/5,439/13,727, about 15%. This improves algorithmic
work and scratch requirements; the isolated whole-compile timings do not establish
a speedup.

Release inlining transports small direct scalar bodies from immutable admitted
templates. It preserves evaluation order, single argument evaluation, intermediate
SSA definitions and separately rounded F32 operations. The initial rule excludes
captures, generic substitutions, effects and proof-bearing interfaces/producers.
The original source bodies remain available; no specialization changes their ABI.

The policy stays fixed: at most 32 callee nodes, depth 2, 16 sites per caller,
floor(caller nodes / 4) growth capped at 256, global output N+64, 8N+1024 visits
and N+256 rewrites. Analysis and physical table growth are preflighted. The pass
reserves the work needed to finish block and live-call lists before spending more
analysis visits, allowing a validated useful prefix when an optional limit is
reached. Internal invariant failures remain failures. Every candidate is
independently validated before lowering. Off/fast tier behavior is unchanged.

`--timings` exposes `inline_sites`, `inline_growth`, `inline_declines`,
`inline_max_callee` and `inline_max_depth`. These count attempted optional work;
a whole-candidate `rewrite_declines` means the emitted program can still be the
baseline. Retained semantic receipts never store expanded caller bodies: callee
edits redo transport after ordinary semantic reuse.

## Measurement method

The previous qualified K1 is `f84aa746934c4b9ef5cc818bf7402f19f07beffb63b558000d30c0cccdbdb14a`.
The installed legacy compiler is `fd2119f5528cb164131e1156d35ba97c434393647f1b326ae5aa154db137d923`
from main revision `1e39b5d8a4268b9edf769c2813d5231abe1c963b`.
Goose remains pinned to `a108677d300cb0e8bbb842c35a353abe67a20c6c`.

Five sequential counterbalanced pairs retain every sample, process wall/CPU/RSS,
source/compiler/Wasm hashes, exact checksums and separate instrumented phase
builds. Final synthetic runtime uses one million warmup and 500,000 timed calls;
it includes the JS/Wasm boundary. The isolated structural ablations use short
runtime checks only and support compile-time attribution, not runtime claims.
The two new loop kernels vary seeds and check exact JS reference results: 1,024
wrapping-integer recurrence steps or 128 separately rounded F32 affine steps per
call, with 2,000 warmup and 20,000 timed calls. They compare release with fast on
the same compiler, isolating inlining from the existing local rewrite kernel.

CPU placement, frequency and filesystem cache are uncontrolled on a shared
workstation. Unrelated game/build activity was observed and recorded. Paired
ratios and full ranges accompany medians; cross-batch absolute timing comparisons
are not evidence of a speedup. No gdev migration, universal performance parity
or compiler rebuild-time improvement is claimed.

## Attribution

Native sampling of the prior qualified compiler used generated C with `-O2 -pg`,
100 fresh compilations per workload and tmpfs output. It is attribution only.
Proof-heavy compilation spends sampled self time in Wasm lowering (17.5%),
validator structure checks (7.1%), proof order graphs (5.1%) and resource planning
(4.7%). Domain-heavy compilation spends 20.9% in `validate_core` and 11.9% in
`type_node`; modules spend 16.7% in `validate_core` and 10% in `closed_interface`.
Raw reports, commands and input hashes are archived.

The Core-borrow-only release ablation gives paired median whole-compile ratios
of 0.899 for modules, 0.920 for proofs, 0.908 for domains and 0.917 for diamonds.
Calls are unchanged (1.002). The Tarjan-only proof-128 ratio is 0.999: its work
reduction is real, but a whole-compile time win was not resolved in these samples.
Both ablations produce byte-identical Wasm to the previous K1. They have focused
regression evidence; full qualification applies to the final combined candidate.

## Final qualified results

The final executable is `ca49141eea94f5f3e1cb3d87930bb41b5409e5dedc777b991c6ed6b2eebcf527`,
input manifest `32c050991a86eec699074c07a52add676ebef9f795685c3f6490743ab054b928`.
The complete release gate passed **115 native entries, 88 Deno integration tests,
editor scopes and 29 formatter round trips**. [The evidence manifest](results/structural/manifest.json)
pins all 191 qualified inputs and 1,177 measured records, including the two
isolated structural ablations and the additional engine controls below.

Fresh compile medians against the previous qualified K1, optimization off on both
sides, at scale 128 (chains 127):

| Workload | Previous K1 ms | New K1 ms | Paired median new/previous |
| --- | ---: | ---: | ---: |
| Independent functions | 5.10 | 4.54 | 0.895 |
| Shared callee | 5.07 | 4.35 | 0.925 |
| Call chain (127) | 5.54 | 5.05 | 0.879 |
| Diamonds | 17.62 | 15.40 | 0.910 |
| Generic calls | 5.18 | 4.74 | 0.910 |
| Captured closures | 8.74 | 7.92 | 0.885 |
| Imported modules | 12.11 | 11.19 | 0.932 |
| Guarded arithmetic | 29.14 | 24.84 | 0.851 |
| Static domains | 15.04 | 13.09 | 0.869 |

These paired ratios indicate roughly 7–15% less whole-process compile time on
these large synthetic cases. Off-tier Wasm is byte-identical throughout the
previous/new K1 matrix, so differences in its runtime timings are measurement
variation, not a compiler runtime improvement. CPU/RSS distributions and all
smaller scales are included in the JSON summaries.

Separate retained comparisons at 128 callers give body edits 6.96 → 6.29 ms
(paired ratio 0.928), unchanged requests 7.31 → 6.34 ms (0.887) and interface edits
6.26 → 5.36 ms (0.875). All ten revision cases, including rejection and rollback,
are retained. The semantic reuse rules did not change.

Single instrumented phase builds locate the improvement mainly in validation:
proofs 11.37 → 6.71 ms, domains 4.96 → 3.29 ms, modules 3.58 → 2.36 ms. These are
attribution samples, not repeated timing estimates. Proof-heavy completion still
takes 9.31 ms and lowering 3.31 ms in the new phase sample. Domain planning takes
2.87 ms. The graph-work reduction has not established a separate wall-time win.

## Inlining results and limits

The unmodified 128-diamond corpus retains 25 sites and eight added operations
within its original 12,288-visit budget, with no whole-candidate decline. Only
`run_0` through `run_8` change; the other 119 exported call graphs are byte-identical
to fast. Code bodies grow seven bytes in total. Type, function, table, memory,
export, element, data and manifest sections are identical. Call wrappers and
memory geometry are unchanged. The fixed caller-growth rule declines the tiny
shared-callee/module wrappers; generic calls remain outside initial eligibility.

Runtime has **no established general improvement** from this initial inliner.
The recurrence kernel has one site/+3 operations and a paired release/fast ratio
of 1.010; the affine loop has two sites/+2 operations and a ratio of 0.980. Neither
is a resolved gain in these samples. Release compilation also pays for optional
analysis, cloning and independent candidate validation.

The initial mixed-family diamond run measured 46.81 → 57.48 ns/call (fast →
release, paired ratio 1.228). This prompted a bounded control, not replacement of
the original samples. Five fresh Deno processes with counterbalanced tier order
reversed the result: 55.39 → 45.93 ns, paired ratio 0.796 (range 0.775–1.199). With
`--v8-flags=--no-liftoff`, the same fresh-process control measured 14.01 → 13.50 ns,
paired ratio 0.989. Process/engine state and host variation affect these results;
the data do not establish a consistent diamond speedup or slowdown. The optimizing
engine control is separate from ordinary default-engine performance.

No benchmark-specific optimization, weakened budget or language change was added
to manufacture a win. The inliner is a qualified optional mechanism, not evidence
that more inlining alone will close the runtime gap.

## Legacy comparison and next decisions

The current off-tier legacy comparison is reproduced in the repository README.
Imported-module compilation is now near parity (10.71 vs 10.61 ms, legacy vs K1).
Proofs remain slower (22.56 vs 25.40 ms), as do domains (7.35 vs 13.23 ms).
Default-engine runtime still trails on diamond graphs and generic calls; the
structural changes deliberately do not change off-tier executable bytes.

The next compiler targets are remaining completion/evidence work and validation
/type traversal or static-domain planning, guided by the preserved profiles.
For runtime, investigate shared generic slot/adapter overhead and engine-stable
whole kernels before adding more rewrite rules or widening inlining policy.
Retained transport and Goose/C rebuild iteration are separate measurements.
Main, the installed compiler and historical evidence packages remain untouched.

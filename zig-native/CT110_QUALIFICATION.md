# CT110: shared effect proofs and bounded admission work

The complete compiler gate, seven final release pairs, held-out execution and
local installation checks pass. The [work record](../COMPILER_CT110_WORK.md)
retains the diagnostic candidates, rejected experiments and limitations.

## Candidate and controls

Baseline: CT109 commit `6a465767b779299bc35cf2eb809bc3e59e0e291b`. Baseline
native SHA-256:
`6b9ed919a48f4d98b7faaedee3ac25cd87e931601189eb1d1d4239fbd3842b1c`. Candidate 4
native SHA-256:
`b0ebc5ecf07f962665fcc3cf879f5e955eb07f1341a0f2b5b8d783b963228dd2`. Compiler
identity-file SHA-256:
`7b60f0b6434e4103e0c7355ab475e4f7b132554c8959ca42971be248a3644259`.

The frozen 554-file gdev/Ink/stdlib manifest remains
`d54b0078ea7c8f94fae131e19f7ea46699891d6aba14b61803386595e9704146`. The game
uses 189 modules, optimized codegen, four backend workers, a 200-million
inference budget and no persistent restart cache. Measurements compare fresh
builds, retained edits and reverts separately. Independent fresh controls and
the existing exact Wasm hashes remain mandatory.

The host is an AMD Ryzen 7 7800X3D with 16 logical CPUs. Other applications
remain active. This task's builds and test execution finish before performance
measurements start. CPU includes all process threads at 10 ms tick resolution;
wall time excludes process/project opening. Neither is a quiet-host guarantee.

## Implemented changes

1. Checked-scheme reuse records transitive requirement headers, using the
   recorder's bounded deduplicated output as its traversal queue. Admission
   compares schemes, public binders, closed rows, flags and diagnostic positions
   in freshly checked Core. Actual body reads still record body dependencies.
   Unprojected external alias chains decline the optional proof. Archive key v9
   prevents older observation semantics from being reused.
2. Closed operation-argument certificates follow an exact immutable label span
   across chronological row headers, using the existing four fallback slots.
   Tails and depth remain checked; physical writes, rollback and saturation
   invalidate proofs. No new cache allocation or approximate equality is used.
3. Rebuilt rows share label slices already owned by their effect store, while
   retaining independent headers, tails and historical cursors. External input
   slices are copied. Temporary principal-graph and scheme-import arrays use
   small stack buffers with heap fallback; persistent output remains owned.
4. Executable admission memoizes successful structural imports of named jobs and
   closures without static captures in one exact importer/generator pair.
   Dynamic reads and full job admission still run. Multi-root capture matching
   prepares a graph once, preserves each root's depth walk and rolls back new
   anchors on decline or OOM. Source-only plans are limited to 64 plans and
   65,536 positions per importer; current-value matches are never cached.

Diagnostics now export structural-request memo counters, inferred/callee
requirement counts at source declines, and scratch statistics from both capture
matching owners. Earlier zero scratch counts omitted the fragment matcher.

## Seven alternating release pairs

| Workload / phase      | CT109 wall | CT110 wall | CT109 CPU | CT110 CPU | Paired CPU change |
| --------------------- | ---------: | ---------: | --------: | --------: | ----------------: |
| Game / fresh          |    7.640 s |    7.335 s |   7.920 s |   7.600 s |             -2.9% |
| Game / literal edit   |    3.134 s |    3.034 s |   3.390 s |   3.270 s |             -4.4% |
| Game / literal revert |    2.858 s |    2.735 s |   2.860 s |   2.730 s |             -4.6% |
| Game / body edit      |    5.234 s |    5.035 s |   5.390 s |   5.200 s |             -3.0% |
| Game / body revert    |    5.215 s |    4.912 s |   5.200 s |   4.920 s |             -3.8% |
| Devtools / fresh      |    0.742 s |    0.741 s |   0.790 s |   0.780 s |             -1.3% |

The final column is the median of within-pair CPU changes, not a ratio of the
two CPU medians. All seven pairs are retained. Fresh CPU guards, strict output
hashes, independent fresh controls, restoration and input pins pass. Host load
moves from 5.1 to 3.0. Profiling is off for these measurements.

Candidate literal wall ranges 2.982–3.532 s; body wall ranges 4.974–5.257 s. The
gains are modest. The 10% literal / 20% body acceptance targets, two-second goal
and sub-second goal remain open despite the much larger scan reduction.

Median lifetime peak RSS is effectively flat: 481.93 → 481.37 MiB fresh, 696.86
→ 696.30 MiB after the literal edit, and 753.95 → 755.13 MiB after the body
edit. These peaks include earlier requests in each retained process;
allocation-request savings do not establish lower live or retained memory.

## Deterministic screen

Both the Safe/noLLVM screen and final LLVM profile pass the frozen fresh,
literal-edit, revert and body-edit Wasm hashes and confirm these work counts. No
development-binary timings are used for performance claims.

| Operation-label visits |      CT109 |      CT110 | Change |
| ---------------------- | ---------: | ---------: | -----: |
| Fresh                  | 76,384,805 | 21,769,624 | -71.5% |
| Literal edit           | 36,420,954 |  4,983,471 | -86.3% |
| Literal revert         | 36,201,842 |  4,948,258 | -86.3% |
| Body edit              | 58,470,836 | 19,370,768 | -66.9% |

## Attribution and allocation traffic

The final same-profile pair is diagnostic, not a latency distribution. Literal
inference thread CPU is 1.491 → 1.380 s; body inference is 3.822 → 3.954 s in
this one pair. The latter variation does not establish a body-inference gain;
the seven unprofiled pairs above remain the end-to-end comparison.

The candidate spends 1.954 s of literal wall and 1.807 s of body wall outside
inference. Its literal exclusive thread CPU includes 441 ms lookup, 289 ms
evaluation, 181 ms constants, 90 ms layouts and 82 ms query validation. Assembly
takes 205 ms wall. These clocks have different scopes and must not be summed as
though they cover the same threads or phases.

Most eliminated label visits were cheap certificate hits: literal closed
operation hits fall 36,191,412 → 4,773,982, while actual argument-height checks
fall only 227,894 → 207,977. Literal/body inference regions remain 2,934 /
7,216, with 105,808 / 185,102 scopes. The expensive solves and graph
construction largely remain.

| Solver + scratch requests | CT109 bytes (decimal GB) | CT110 bytes (decimal GB) | CT109 allocation calls | CT110 allocation calls |
| ------------------------- | -----------------------: | -----------------------: | ---------------------: | ---------------------: |
| Fresh                     |                   3.2196 |                   3.2219 |              5,192,286 |              5,190,532 |
| Literal edit              |                   1.0904 |                   1.0890 |              1,456,513 |              1,455,799 |
| Body edit                 |                   2.0454 |                   2.0439 |              3,940,921 |              3,939,275 |

These are cumulative logical allocator requests, not live bytes or OS memory
traffic. Fresh requested bytes rise slightly despite fewer calls. This batch
does not establish a broad memory improvement. Structural request memoization
avoids 56,133 of 100,750 checks on the literal edit and 51,917 of 95,073 on the
body edit; dynamic admission checks remain active.

## Remaining costs and limits

The three body principal misses remain: `walk_material` has one inferred and one
callee requirement; `haul_all_observed` has four inferred and three callee
requirements. They cannot use the written-requirement header proof. Body
principal hits remain 17/20. Further reuse needs a proof of the inferred
requirement computation or an incremental constraint design.

The final literal profile still performs 1,742 fragment graph matches and visits
3,978,261 positions. Its separate capture-plan cache has zero calls on gdev, so
that change is not a measured gdev benefit. Graph-copy stack buffers save only
hundreds to about a thousand allocation calls among millions; they are not a
broad solution to solver memory traffic. Repeated refinement and specialization
solves remain. Sub-second ordinary edits are not established.

Two partial-row cache experiments produce no work reduction and are removed. The
work record and raw diagnostic pairs retain their negative results.

## Verification

The selected development cycle passes in 25.54 s, including Safe/noLLVM
compilation of all 2,576 native laws, 99 selected native laws with sampled
allocation faults, 56 guest tests and zero Zig lint findings. The tight
`chain_generic N=64` release allocation budget also passes unchanged.

The complete gate passes 2,576 exhaustive native laws, 1,656 guests, 48 smoke
tests and 57 tooling tests. A separate final Zig lint checks 522 files with zero
findings. It uses frozen sibling fixtures and exact pins for 1,003
source/test/client/tool inputs.

Native execution takes 1,228.48 s across two shards. The first gate then finds a
guest-fixture cleanup race: Linux's detached cache writer outlives `dispose()`.
The resource test now joins cache-key locks before deleting its directory,
matching the existing restart-cache tests. No compiler behavior or assertion is
weakened. The first run and failure logs remain preserved.

The completed gate (`run-82aeec91e04fc306`) verifies and resumes the exact
native evidence (`run-93b2de9b77aab21b`) and reruns guests/local checks in 51.06
s. That is a resumed completion interval, not the total qualification cost.
Release construction takes 318.80 s while native execution overlaps; native
compilation takes 9.70 s. These are observations, not paired compiler-iteration
gains.

Three alternating held-out pairs over 11 cases pass exact fresh/edit/revert
outputs. All 44 independent original/edited Wasm executions across both
compilers pass their result oracles. Coverage includes records, effects,
closures, shared graphs, module edits and lexical generic schemes.

Both `~/.local/bin/blot` and `blotc` are installed and verified from an external
working directory: format/check/build, exact staged/installed CLI/native Wasm,
runtime answer 29 and bundled-guide equality. Native bytes match the qualified
release above. Installed CLI SHA-256:
`4b2841603891fe4464f27f83b60b643bb3d587d33cf4d97fe77f70b7926227df`.
Installation, previous-binary pins and rollback copies are recorded in
`build/install/ct110/installed.json`.

## Evidence

[Raw evidence](measurements/ct110-2026-10-25.tar.gz) contains 282 files
(8,007,241 compressed bytes). SHA-256:
`f27b37e0e5d952b91e59774e0e5500892c51c881cc4554383fa3f06476257f82`.

It includes all candidate profiles, seven final pairs, three held-out pairs and
execution oracles, deterministic screens, source/binary pins, the runtime patch,
development results, failed and completed full-gate logs/journals,
frozen-fixture identity and installation checks. The pre-change CT109 diagnostic
profile is also included. Paths are preserved relative to the repository root.
Native executables and rollback binaries stay local; their SHA-256 pins are
archived.

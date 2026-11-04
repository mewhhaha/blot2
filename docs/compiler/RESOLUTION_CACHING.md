# Chronological resolution caching

Type resolution follows ordered type and effect substitutions, including views
into a future part of that history. It is not ordinary union-find. The reference
path is `types.Store.resolveDepth`; a cache must preserve the same canonical
views and failures at each requested cursor.

## Existing certificates and the future-alias correction

The current-epoch cache is invalidated by type or effect mutation. Solver-owned
principal variables additionally retain node-local certificates. A closed answer
survives unrelated appended substitutions. An open answer watches the remaining
variable's chronological lower bound. Rollback, physical graph edits and
saturated clocks revoke those certificates. The metadata never leaves its solver
owner.

An unwritten future alias needs an additional check. Create a variable's view at
cursor 10, assign a second variable to that view, and resolve the second
variable. The result initially has cursor 10. Nine unrelated writes then bring
the shared clock to 10. Ordinary traversal now returns the unwritten variable's
principal view, with cursor zero. Retaining the cursor-10 certificate would
disagree with the reference path even though the variable itself has no writes.

The correction accepts an unwritten remaining variable only while its view is
already principal or is still beyond the shared clock. The native regression
compares cached and uncached stores through that transition. This corrects the
existing variable cache; it does not implement composite caching. Zig 0.17.0,
the full native suite, all 595 guest/client tests and the source analyzer (287
files, zero findings) pass. The release is pinned at
`build/bench/future-alias-qualified/blotc`, SHA-256
`2a709b4ca9d93fad58057531f7913ce159e6129aeb59596aff6e5534c6c9c258`. The logs are
`build/bench/future-alias-compiler-gate.log` and
`build/bench/future-alias-analyzer.log`. Composite caching remained separate
work at that milestone.

## Bounded composite cache

The production cache adds a solver-local table with 16 direct-mapped slots keyed
by root and chronological cursor. A complete entry owns its result ID and at
most eight unresolved type/effect dependencies. No pointers into growable
storage are retained.

Certificates describe the normalized result's unresolved frontier. Monotone
appends cannot rewrite the already consumed prefix. The latest write of each
remaining variable must still match. Unwritten future type views additionally
watch the shared clock. Physical type generation, physical effect generation,
rollback and saturated counters invalidate or decline the cache. The ordinary
resolver remains the fallback for unsupported or oversized proofs.

Discovery visits at most 256 nodes with a 128-entry traversal stack. The default
cost policy records only normalizations creating at least four type nodes. The
table allocates once; an unchanged first query acquires no retained storage.
Publication uses a complete local record. Existing same-epoch hits are checked
first. The table is enabled only in solver stores that request closed-graph
certificates and also admits variable roots whose normalized result is
composite. Historical queries keep their exact root/cursor key. The experiments
below explain why cheaper normalizations do not acquire certificates.

## Qualification record, 9 October 2026

The initial admission experiment failed the existing no-allocation law for an
unchanged aggregate query and was rejected. A corrected frontier candidate
passed the focused native laws but increased fresh compiler CPU in a three-pair
screen. Moving the ordinary epoch-cache hit before frontier validation still
increased fresh CPU from 887 to 952 ms in the next screen. Neither version was
landed. The latter release has SHA-256
`decd3f0436a7dbd4c99cca4ead671e94b0b011df1f74ec0d4fdd8152c4d38953`; its complete
retained records are under `build/bench/composite-cache-epoch-first/`.

One copied scratch runner initially reused the preceding experiment's output
directory. Its generated artifacts were moved to that corrected directory with
the original command paths recorded in the manifest. The overwritten earlier
screen is not a qualified raw-data record. Its remaining patch and the explicit
record of that limitation are under `build/bench/composite-cache-frontier/`.

The fourth candidate passed all 55 native resolution/ownership laws and 14
executed-Wasm laws. These include generated chronological histories, physical
edits, rollback and recycled IDs, future views, cache saturation, allocation
failure, callbacks/effects, dependencies, checkpoints and failed revisions. The
fingerprint oracle traverses List and cursor children as well as the other
composite shapes.

Its release SHA-256 is
`2cf284a468cbfc51ef9625d73ecaa7cd448622518f18d58b6d36d98748999d5f`. The baseline
contains only the future-alias correction and has SHA-256
`2a709b4ca9d93fad58057531f7913ce159e6129aeb59596aff6e5534c6c9c258`. The initial
three-pair gdev screen measured 972/981 ms fresh CPU, 1,120/1,140 ms dependency
population, 260/260 ms first edit and 250/240 ms subsequent edit,
baseline/candidate. Requested fresh allocation fell from 321,026,930 to
320,341,190 bytes and type nodes from 547,540 to 542,591. Work counters and Wasm
were identical. Host load was 39.5–41.2 on 16 CPUs; these are screening results,
not an idle-machine performance claim.

Seven alternating pairs measured 944/957 ms fresh CPU, 1,100/1,100 ms
population, 250/260 ms first edit and 230/210 ms subsequent edit. A separate
seven-pair restart batch measured 1,042/1,049 ms cold population, 640/673 ms
process restart, 1,110/1,120 ms retained population, 250/260 ms first edit and
230/230 ms subsequent edit. No-op CPU was below the retained counter's 10-ms
resolution. Neither comparison establishes a compiler speedup. All Wasm
comparisons passed.

The corpus comparison also passed: 305 cases, 610 invocations, 244 successful
cases, and no diagnostic, semantic or Wasm differences. Pins, source patches,
commands and raw samples are retained under
`build/bench/composite-cache-variable-frontier/`. Its full native suite and all
595 guest/client tests pass. The analyzer found one overwritten-owner warning
when installing the initially empty entry buffer; this version was not landed.

The next candidate removes the visit-counter increment from release execution
and explicitly releases the old empty owner before installing the buffer. The
analyzer checks 288 files with zero findings. Its release SHA-256 is
`a069fcabcc9199bce1dcdd87be84cea119fd4a0da437ed34cc7c6433161f3d6e`, preserved
under `build/bench/composite-cache-owner-transition/`. Seven no-cache pairs
measure 959/971 ms fresh CPU, 1,110/1,110 ms population, 260/260 ms first edit
and 220/220 ms subsequent edit. Wasm and work counters match. The remaining cold
overhead is not justified by these results. Seven restart pairs measure
1,045/1,044 ms cold population and 638/659 ms process restart, with 1,110/1,100
ms retained population, 260/250 ms first edit and 220/220 ms subsequent edit.
Its full native suite and all 595 guest/client tests pass. This candidate is not
accepted: the repeated cold/restart costs outweigh the small allocation
reduction in these measurements.

A separate warmup candidate records a bounded root-use hint on the first changed
query and builds a frontier only after a second epoch miss. This hint can admit
unhelpful roots but can never validate an answer: the complete key and
dependency certificate still decide reuse. It aims to avoid allocating and
scanning certificates for one-use roots. Twenty focused native checks pass,
including discovery checks, and the analyzer reports zero findings in 288 files.
Release SHA-256
`671e30f9e1172c0d15b4dcced06c083304af47cecf20689f167ffeb2063d4a1e` is pinned in
`build/bench/composite-cache-warmup/`. Seven no-cache pairs measure 943/935 ms
fresh CPU, 1,100/1,090 ms population, 250/250 ms first edit and 220/220 ms
subsequent edit. Seven restart pairs measure 1,027/1,040 ms cold population,
630/652 ms process restart, 1,100/1,080 ms retained population, 250/250 ms first
edit and 220/230 ms subsequent edit. Same-compiler and cross-compiler Wasm
comparisons pass. Requested fresh allocation falls from 321,026,930 to
320,517,978 bytes. These loaded-host observations still show a repeated restart
cost; the warmup candidate is not accepted for production.

A subsequent isolated probe defers physical-owner activation until the first
certificate is actually recorded. An empty table needs no validity check on
every miss; the complete certificate still controls every hit once records
exist. Focused native checks and the analyzer pass. This probe's release pin is
`e0fbd4b40ef139fda3f322432155d6a9c158f9fd3bd69bee48db36f4fa6110d2`, in
`build/bench/composite-cache-lazy-activation/`. Seven no-cache pairs measure
947/946 ms fresh CPU, 1,090/1,080 ms population, 240/250 ms first edit and
220/230 ms subsequent edit. Seven restart pairs measure 983/1,026 ms cold
population, 631/648 ms process restart, 1,100/1,090 ms retained population,
240/250 ms first edit and 220/210 ms subsequent edit. Byte comparisons pass. The
cold/restart measurements still do not justify this candidate, which remains
unlanded. It did not complete task 009; a correct certificate alone is
insufficient evidence of a useful cache.

An instrumented development build explains part of the cost. Across 2,089 solver
stores in one gdev build, it observes 640,199 cache misses and 6,730 hits. Of
those hits, 6,381 avoid creating at most two type nodes. The instrumentation pin
is `d2b4277342e93a87796bc4d4e43e02a7b623ef2a12f478a197df9c868b759de3`, in
`build/bench/composite-cache-profile-saved/`; these counts are evidence about
work, not valid timing measurements. A follow-on cost policy records only
normalizations creating at least four nodes and removes the warmup hint table.
Twenty-one focused native checks pass, including the default-policy admission
case and low-threshold certificate/ownership cases. The analyzer reports zero
findings in 288 files. Its release pin is
`f2294ddde4887413ae544850be235a05c5796362fbdc43f05b07475845d17a1a`, in
`build/bench/composite-cache-cost-gated/`.

Seven no-cache pairs measure 943/955 ms fresh CPU, 1,110/1,110 ms population,
240/250 ms first edit and 230/230 ms subsequent edit, baseline/candidate. A
separate seven-pair restart batch measures 1,046/1,035 ms cold population,
650/653 ms restart, 1,110/1,100 ms retained population, 240/250 ms first edit
and 220/220 ms subsequent edit. Requested fresh allocation changes from
321,026,930 to 320,975,430 bytes. Same-compiler and cross-compiler bytes match.
These loaded-host measurements show mixed cold costs and no general compiler
speedup; they do not establish the final performance targets.

A separate Store benchmark resolves a 32-layer array after each of 10,000
unrelated writes. Every result checks all layers and the U32 element, with an
equal checksum in both configurations. Seven alternating pairs measure median
CPU of 9.251 ms with composite caching disabled and 1.089 ms enabled; type nodes
fall from 320,040 to 72. The benchmark sources, executable hashes and samples
are under `microbench/` in the same qualification directory. This demonstrates
the benefit for repeated expensive resolutions, rather than a whole-compiler
gain. The 305-case differential comparison passes with no semantic, diagnostic
or Wasm differences, as do fourteen focused execution laws. Its full native
suite and all 595 guest/client tests also pass.

## Production qualification, 9 October 2026

The cost-gated implementation is accepted in commit `d736d45`. Production
release `0e78ed2c1e6343c41fb92cc1565fc0f11ffa007a74ca869826cf67307ddcb78d` is
pinned in `build/bench/composite-cache-main/`. Zig 0.17.0, the full native suite
and all 598 guest/client tests pass. The analyzer reports zero findings across
289 Zig files. The focused resolution filter passes 41 checks, including
discovery. Logs are `build/bench/composite-cache-main-compiler-gate.log`,
`build/bench/composite-cache-main-native.log` and
`build/bench/composite-cache-main-analyzer.log`. The recorded source hashes,
executable and compiler identity match the production tree.

Three alternating integration pairs against the preceding row/admission release
`1a0be8c0a216346299f7701484287f58675a337fce872272bafeec22a9e9c8a0` measure
954/957 ms fresh CPU, 1,110/1,120 ms population, 250/250 ms first edit and
230/220 ms subsequent edit. The restart batch measures 1,030/1,024 ms cold
population, 637/639 ms restart, 1,100/1,090 ms retained population, 250/260 ms
first edit and 220/230 ms subsequent edit. No-op samples are at the 10-ms
accounting limit. Every fresh/retained/restart and cross-compiler byte
comparison passes.

Requested fresh allocation falls from 321,139,550 to 321,088,050 bytes; type
nodes fall from 547,540 to 546,936. These loaded-host measurements show small,
mixed timing changes. Acceptance rests on the complete validity/ownership laws,
the measured benefit for repeated expensive resolution and the bounded cost
policy. This is not a general compiler-speed claim. The final cold, edit,
region-size and cumulative-allocation targets remain open.

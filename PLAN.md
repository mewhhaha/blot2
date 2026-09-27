# Compile speed: numeric identities, reuse, and generic sharing

Updated 2026-09-27 after the user's request to prioritize string inefficiencies
while retaining fast iteration and the broader compiler work. This is the active
execution plan. The previous sequence is preserved in
`build/perf-overhaul/PLAN.original.md`; the intended language and compiler
semantics remain in [CONSTRAINTS.md](compiler/CONSTRAINTS.md).

## Next result

Native regression triage now has two measured Bend-source improvements:
replacing string-index branch closures with a direct tail loop reduced
matching-version gdev cold compilation from 126.9 to 85.4 seconds (three
alternating pairs), with identical Wasm and a similar body-edit improvement.
Retaining owning string roots during name comparison then reduced a fresh
lookup-only control from 88.2 to 78.8 seconds (another three pairs), with body
edits at 86.2 to 75.9 seconds and identical Wasm. Both source changes and their
verified artifacts are installed. See compiler/COMPILE_SPEED_RESULTS.md.
Compilation remains expensive; continue measuring the remaining serial work
before expanding a redesign. Generated output remains unchanged.

The first two Blot-side identity catalog experiments are complete and parked.
Both pass targeted correctness and game behavior checks, but neither improves
the measured cold/edit cycle. See compiler/COMPILE_SPEED_RESULTS.md. Resume the
preserved source-derived generic-body execution and collector checks; a future
identity slice must carry resolved IDs through repeated consumers instead of
adding another string-to-ID catalog per phase.

Keep spelling identity (Symbol ID) separate from declaration identity
(Declaration ID), so equal names in different scopes can resolve to distinct
declarations. Use numeric indexes and sets after resolution, retain source text
for diagnostics, and keep request-local IDs out of persistent cache keys and
public packets. Packed strings are a separate text-storage experiment, not the
identity fix.

The existing dependency SCC traversal already uses numeric IDs. The saved
profile points instead to binding lookup and repeated name membership. Choose
one owner scope from its caller stacks, index it once where possible, and
measure the entire compile including catalog construction and string-to-ID
conversion. A narrow indexed lookup is an intermediate slice, not completion of
symbol interning across the compiler. Do not attribute the historical 134-second
compile entirely to strings.

Preserve and then resume release specialization reuse and development
generic-body sharing, including inferred requirements, effects, closures,
constant evaluation, safe caches, and eventual gdev integration described in
CONSTRAINTS.md. Validate small working slices before expanding them; keep the
existing benchmark reusable.

The benchmark is reusable. The previous numeric-index experiment only removed a
Patricia lookup check; it was parked after an unfavorable cold/edit tradeoff and
did not test symbol or declaration IDs. Bend has moved to 2.0.32, so rebuild
both comparison sides with the same latest release. The next checkpoints are:

1. Completed two isolated indexed scopes (row ownership and shape bindings).
   Correctness passes; neither game screen supports adoption. Preserve both
   experiments and the distinction between Symbol and Declaration IDs. Revisit
   broader resolved-reference migration with a concrete reuse boundary; require
   three alternating cold/edit A/B pairs before adopting a candidate.
2. Resume verification of preserved collector fixes. Regression exports are
   separated from production entries. The r25 candidate passes full Bend 2.0.32
   proof and 475 collector/source/development JS tests, with no failures. This
   resolves the remaining computed-producer evidence case and corrects the
   standalone local-key fixture. Session verification and the separate State.run
   pre-key draft are next; these are isolated candidates, not live adoption.
3. Complete release collector admission for real gdev-derived ECS get/set calls,
   including State.run. Assert complete-key reuse and actual collector
   execution, then measure compilation and behavior against the baseline.
4. First prototype complete: one source-derived generic body runs at U32 and F32
   with correct results. Proof and 58 focused tests pass. Eight alternating
   pairs measured 11.04ms release versus5.60ms private sharing for this exact
   small program; no game-wide gain is established. Preserve this checkpoint
   before widening source admission.
5. Complete the remaining effects/reflection, public mode, and cache
   integration; adopt development mode in gdev only after parity and an
   iteration-speed gain.

The main developer reviews and verifies all agent changes. Source edits remain
isolated until their checks pass; preserve concurrent work and prior
checkpoints.

## Starting point

- Use the functionally verified r31 compiler source as the comparison baseline,
  with the loader compatibility fix needed by the latest Bend. Preserve its
  existing correctness evidence, but distinguish it from verification of a fresh
  build. Use the preserved r8 collector as a candidate, not as baseline
  evidence.
- Use the latest released Bend available for each new build batch. Record the
  version and keep compiler, Base, and JS loader matched throughout the batch.
  Rebuild both comparison sides when the toolchain changes; historical results
  remain version-specific.
- Freeze one current gdev source snapshot, its std inputs, compiler options, and
  one deterministic function-body edit. Reuse the existing captured gdev
  workload if it matches the behavior being measured. Never edit live game files
  to construct a benchmark.
- Keep the main(host), for ever, memory, and host migration work intact. Its
  passed tests are useful evidence, not an obligation to rerun the whole game
  suite before every performance experiment.

## 1. Establish the actual iteration path

Measure gdev's existing `createBlotCompiler` behavior through the JS backend:

| Case              | What must happen                                                                                         |
| ----------------- | -------------------------------------------------------------------------------------------------------- |
| Cold startup      | Fresh host process, project load, compiler setup, compilation, and Wasm available                        |
| Unchanged request | Reload/key the project and reuse gdev's previous artifact; record this separately as an output-cache hit |
| Body edit         | Reload one changed source and perform the compile that gdev actually uses                                |

On a body edit, gdev re-reads the import graph, reuses parsed unchanged files,
and compiles the whole project with a fresh source compiler. Do not describe
that measurement as reuse of an incremental compiler session. The JS incremental
API accepts a single source string and rejects project imports. It and the
private native-session logic are separate paths; benchmark them only if an
experiment specifically changes that behavior.

Build only `compiler/main.bend` -> `compiler.js` for this first experiment,
using the production upstream loader recipe and unchanged generated output. The
public JS project/source compile path does not need `native_session.js`,
`native_output.js`, or a native executable. Confirm imports in the runner before
building. Keep proof on Bend-source builds; reuse matching artifacts for harness
or workload-only edits. Avoid tasks that implicitly rebuild all targets.

The first deliverable is one reusable command accepting baseline/candidate roots
and the frozen workload. It must record end-to-end wall time, project/setup and
compile intervals, peak process memory, tool/runtime versions, input/artifact
hashes, raw samples, and a small deterministic guest behavior check. Record Wasm
size and available work/reuse counters separately from timed samples. Reuse the
existing gate lock, normal-priority wrapper, and measurement helpers; do not
create another revision-specific runner or receipt framework.

Take a small baseline sample and one profile of the real compile path. Use that
profile to choose the first change. Time project load, compiler setup, and the
compile call externally; use a V8 CPU profile for internal attribution in the
fused source compiler. Do not substitute the single-file incremental API's phase
stats for gdev's project timings. If source instrumentation is necessary, use a
separate diagnostic build. Keep instrumented measurements separate from
uninstrumented latency results.

## 2. Test one hypothesis

Write down the expensive work, the proposed reduction, and the observable
counter or phase that should change. Make the smallest general compiler change
that tests it. Do not add new language syntax, a public dev mode, or
game-specific compiler rules to obtain a timing result.

Start with one behavior smoke test and targeted correctness tests for the
changed path. For a new index, first screen its complete setup and repeated-use
cost in a small differential experiment; keep both sides inside equivalent
compiler/host conversion boundaries. A clear synthetic regression can reject a
design early, but a synthetic gain does not establish a game compile gain. Then
run one game A/B screening pair. Park a clearly unhelpful or inconclusive
candidate without expanding the run; a screening pair cannot establish a gain.
For an adoption candidate, run three alternating A/B pairs with identical
inputs, options, toolchains, process lifetimes, and measurement boundaries.
Measure cold and edited requests separately. Start each warm/edit sequence from
the same initial state; do not accidentally time an unchanged-result hit as a
body edit. Verify that the edit changes the project key and reaches compilation,
and that the unchanged request takes the output-cache branch.

If the result looks promising, extend to at least five pairs. Retain every
sample and report medians, spread, and paired differences. Run only one build,
test, or benchmark at a time. Do not rerun merely to obtain a favorable number.

Proceed when the timing improvement is repeatable beyond the observed variation,
the expected work reduction occurs, and behavior remains correct. A regression
or inconclusive result is a completed experiment: publish it and revise or park
the change. Fewer generated bodies alone do not establish faster compilation.

Use JS measurements for fast screening. They do not establish native CPU gains
or native worker scaling. Native performance confirmation belongs after a
promising result, before making those claims or accepting a native speedup.

## 3. Expand only after the first useful result

For release specialization reuse, test one real gdev-derived `ecs.get`/`ecs.set`
workload. Require proof that the collector handles those calls, records complete
keys, and reduces preparation/checking/emission work. Record fallbacks
explicitly; a successful legacy fallback is not collector performance evidence.
Identity or arithmetic examples can diagnose plumbing but cannot establish an
ECS gain. If admission requires substantial implementation, split it into
independently verified steps while keeping this workload as the integration
target.

For generic body sharing, first support one generic function at two concrete
types with correct results, one shared emitted body, and measured compile time.
The existing closed development ABI prototype cannot test that hypothesis: it
currently rejects generic evidence. Full effects, reflection, public mode
options, and gdev dev-mode adoption come later.

Before landing a compiler change, complete its required proof, relevant compiler
regressions, behavior/diagnostic parity, and performance acceptance checks.
Broaden testing when the affected paths warrant it. Repeat browser, GPU, or
long-running memory suites when their behavior is affected or unresolved
evidence requires it. Keep local milestone commits; never push or commit in
gdev.

## Checkpoints and ownership

Preserve the r8 collector fixes, curried-call work, State.run pre-key draft,
regression-entry split, and development ABI overlay at their current
checkpoints. Resume them in separate working copies. The five M3 architecture
slices define the required final behavior; focused measurements remain
intermediate checkpoints.

The main developer owns implementation, integration, the serial proof/build/test
gate, performance measurements, and final review. Per the latest user
instruction, continue without subagents; their existing isolated work remains
preserved. Keep contracts and file ownership explicit; do not claim a milestone
complete from source-only work.

Every experiment ends with a short result: exact command and inputs, correctness
outcome, timings and work counts, limitations, and the next decision. Update
`compiler/COMPILE_SPEED_RESULTS.md` as evidence arrives rather than deferring
reporting until all M3 slices are complete.

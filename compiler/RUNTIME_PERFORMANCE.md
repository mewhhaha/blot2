# Runtime data-path review

Baseline: main `ac59fb68f98780e168ce01fa39410b1a6ef54efd`.

This change distinguishes execution of emitted Wasm, the guest/host boundary,
and compiler throughput. It does not claim to eliminate every performance
problem or introduce parallel guest execution.

## Findings and changes

### Array marshalling

`guest.ts` previously loaded/stored each numeric array element through a
DataView and a JavaScript number in both directions. Large callbacks and numeric
packets paid this cost on every crossing. The little-endian fast path now
transfers the exact view range with a bulk byte copy. The big-endian path swaps
words explicitly. Neither path performs floating-point conversions.

Results remain independent copies. Range checks, argument validation, header
encoding, arena reset, host capability checks, and fresh views after memory
growth are retained. F32 signed zero and NaN payload bits survive an identity
array round trip. This is not a zero-copy or shared-memory ABI change.

### Runtime array initialization

`wasm.bend` previously emitted one store/index/bounds/branch cycle per element
for `@array.fill`. The new implementation initializes up to 32 words, then
copies the initialized prefix in bounded doubling steps. The last copy is
limited by the remaining length. This emits logarithmically many bulk-copy
operations while still doing linear total memory work.

`memory.fill` is not suitable for arbitrary words: it repeats a byte, not a U32,
F32 or reference. Copying the initialized prefix preserves all word patterns and
the existing immutable sharing semantics. The empty-array case, Wasm32 overflow
checks and eager evaluation of operands remain unchanged. The extra temporary
has a separately reserved local slot.

### Parser input construction

`syntax.ts` previously split the full source slice into one JavaScript array
entry per UTF-16 code unit, edited integer and clause markers, then joined it.
`parser_source.ts` now joins unchanged slices and small replacement spans.
Declaration reparses binary-search the sorted clause markers rather than
rescanning markers belonging to earlier declarations. The lexer remains the
source of truth; this is not a second parser or a change to string semantics.

Differential tests compare the exact old/new parser input, including Unicode,
CRLF, high U32 literals, annotation clauses and declaration-sized reparses.

### Work queues and concurrency

`CompilerWorkers` and the source loader's bounded-read waiter queue used
`Array.shift`, which repeatedly moves the remaining backlog. They now share an
amortized constant-time FIFO with cleared consumed slots and periodic
compaction. Tests cover compaction, reuse, 4,096 queued real-worker jobs, and
rejecting active/queued jobs on disposal.

Worker counts, bounded read fanout and deterministic dependency/error ordering
are unchanged. Starting more workers is not automatically an optimization:
stateful effects cannot be executed concurrently without a defined ownership and
ordering contract. This PR does not add threads to generated guest code.

## Measurement and validation

The Runtime performance workflow builds both the pinned baseline and candidate
with Bend 2.0.32 and its matching official loader. Generated Bend C/JavaScript
is not patched. Reference module builds are sequential to bound CI peak memory.
A separate native job runs the compiler regression suite. Its status must be
checked independently of the JavaScript hot-path benchmark.

```sh
# In each checkout, using the same Bend, Bun and Deno versions:
deno task generate:parser
python3 /path/to/candidate/scripts/build_runtime_reference.py "$PWD"

# In the candidate checkout:
deno run --allow-read --allow-write=build compiler/runtime_bench.ts /path/to/baseline
```

`build/runtime-performance.json` records eleven alternating baseline/candidate
samples, per-operation medians and their ratios. Inputs and full fill results
are validated outside timed sections. The workflow retains raw reports and
source revisions. Timings are diagnostic, not flaky CI pass/fail thresholds.

The cases isolate runtime fill, copied U32/F32 ABI round trips, parser
normalization and queue draining. Compile/build/startup time and rendering are
not included. Small and large inputs are both measured to reveal crossover
costs. These microbenchmarks do not establish an application-wide speedup.

## Remaining boundaries

The emitted arena's allocation and conservative collection costs, persistent
state/callback patterns, closure allocation, repeated immutable updates and
application-specific query/render algorithms still need workload profiles. The
repository's existing compiler memory and concurrency investigations also remain
relevant; these changes do not fix suspected upstream Bend defects. There is no
new runtime string representation or rope API in this PR: the string improvement
is compiler source preprocessing, not an unsupported promise about guest
strings.

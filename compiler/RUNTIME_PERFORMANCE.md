# Runtime data-path review

Integration baseline: main `2d44737bbe265d75b0264bad78b810c87ff6c024`. The
recorded earlier measurements retain their original revision identities.

This change distinguishes execution of emitted Wasm, the guest/host boundary,
and compiler throughput. It does not claim to eliminate every performance
problem or introduce parallel guest execution.

## Findings and changes

### Array marshalling

`guest.ts` previously loaded/stored each numeric array element through a
DataView and a JavaScript number in both directions. Large callbacks and numeric
packets paid this cost on every crossing. The little-endian fast path now
transfers the exact view range with a bulk byte copy for packets larger than 32
words. Smaller packets avoid the extra byte views. Big-endian hosts and shared
input buffers use explicit word reads/writes. Capturing the input length once
bounds the copy even when a shared buffer can grow. Shared input reads preserve
the U32 no-tear behavior, not a whole-array snapshot under concurrent mutation.
No path performs floating-point conversions.

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
CRLF, high U32 literals, annotation clauses, contextual imports, selectors, and
declaration-sized reparses. Static memo-cell roots remain traced by the
collector alongside the new layout bits.

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
with Bend 2.0.34 and its matching official loader. Generated Bend C/JavaScript
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

## Pointer-free array tracing

This section describes the initial direct-expression optimization. The
subsequent [layout-propagation pass](LAYOUT_PROPAGATION.md) extends it through
local bindings and product fields, and also recognizes scalar-only tuple and
record payloads.

The arena now distinguishes its transient mark bit from a persistent
pointer-free layout bit. Runtime numeric/boolean/unit literals, scalar primitive
results and array lengths provide sufficient layout evidence for fresh array
fills, literal arrays and checked homogeneous array updates. Unknown locals,
projections, calls, nested arrays and closure values do not provide that
evidence. They retain conservative tracing; no pointer classification is guessed
from numeric bits. Static constants and host allocation headers are not changed.

A marked leaf remains live but is not added to the trace work list. Sweeping
preserves its layout bit, and allocating a reused block clears it before the new
payload is installed. Pointerful objects still trace their children, including
shared cycles and pinned pre-loop edges. Collection cadence, pinning watermarks
and the guest ABI are unchanged. Scratch bitmap clearing uses a bounded
`memory.fill` instead of a word-at-a-time loop.

The readable WAT and its generated Bend encoding are checked together. Tests
cover scalar/pointer collisions, layout-bit reset on reuse, mixed-graph exact
reachability, negative-zero words and long-lived scalar/reference-array loops,
including arrays of closures whose captures must survive collection. Four
constructor-level laws protect the conservative classification boundary; they
are not a formal proof of the complete garbage collector.

`compiler/gc_bench.ts` compares complete loop invocations against a separately
built previous PR head (`4bfca4a`), isolating collection from the earlier fill
and host-copy changes. It records eleven alternating samples, Wasm sizes,
checksums and memory high-water marks. Unknown-layout and allocation-free
controls remain in the report. Each implementation warms for at least 200 ms and
32 calls, yielding so tiered code can be installed before timing. Fast cases use
equal-sized batches targeting 5 ms for the slower implementation, and times are
normalized per complete invocation. Warmup counts and batch sizes are recorded.
Every measured result is validated outside the timer.

The initial single-call harness showed warmup transients inside its tiny control
samples. Do not compare those earlier medians to the revised harness as an
additional runtime gain; the runtime code is unchanged. Compilation and startup
remain outside the timer.

## Remaining boundaries

The emitted arena's allocation and conservative collection costs, persistent
state/callback patterns, closure allocation, repeated immutable updates and
application-specific query/render algorithms still need workload profiles. The
repository's existing compiler memory and concurrency investigations also remain
relevant; these changes do not fix suspected upstream Bend defects. There is no
new runtime string representation or rope API in this PR: the string improvement
is compiler source preprocessing, not an unsupported promise about guest
strings.

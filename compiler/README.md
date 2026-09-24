# Compiler core

Bend owns language semantics; Deno supplies layout, Baba's field-labelled CST,
native process transport, workers, and execution tests. The compiler
deliberately has no ECS, game, window, rendering, asset, or input vocabulary.

## Run it

```sh
just build
just demo
just demo-host
just compile examples/generic_effects.blot build/effects.wasm
just compile examples/arrays.blot build/arrays.wasm
just check
just bench-native
just bench-cpu
```

Builds require Bend, Deno, and clang 14+ on POSIX. Every compiler build runs
`bend PROOF.bend`. Source-only iterations reuse the compiled executable.
`build:compiler:js` builds the JavaScript reference; `build:compiler:all` builds
both backends for parity checks. The JS build also requires Bun. Its first build
for each installed Bend version downloads four upstream loader files from that
version's release tag into `generated/compiler/bend-<version>/`; subsequent
builds reuse them offline. Release tags must be available upstream for JS
builds. The JS build also emits `generated/compiler/native_session.js` for
direct regression tests of the native session's pure cache-planning logic.

The optimized native build requires Bend 2.0.27. It applies guarded String
comparison, consuming index lookup, borrowed free-variable collection,
closed-type resolution, and a bounded resolver for active substitutions to the
generated C. These kernels preserve the runtime's ownership and reclamation
operations. Bounded type scans fall back to the Bend implementation when they
cannot certify a result. The build checks the source definitions, generated
field layouts, ownership code, and runtime helpers; it refuses an unknown
version or code shape. See
[the String transformer](../scripts/native_string_compare.ts),
[the compiler kernels](../scripts/native_kernels/README.md), and
[cold-compilation results](COLD_COMPILE_RESULTS.md). The
[scaling plan](COLD_COMPILE_PLAN.md) records the remaining gap to 500 ms. The
[type-system redesign study](TYPE_SYSTEM_REDESIGN_STUDY.md) investigates the
broader changes needed for a 100–200 ms source-to-Wasm target. The
[retained-checking implementation](TYPED_CORE_IMPLEMENTATION.md) records the
implemented reuse boundaries, correctness checks, and measured limits. The
[allocation and checking follow-up](TYPE_KERNEL_IMPLEMENTATION.md) implements
the subsequent measured kernels and avoids repeated checking and scans. Bend
2.0.24 passes the ownership regression that required an isolated emitter patch
on 2.0.5, so that obsolete patch has been removed. The build still compiles and
runs [the regression](native_backend_regression.bend) at 1 and 4 threads before
publishing the binary. The native transport uses the new runtime's
constructor-sealing interface; the installed Bend is never modified.

## APIs and incremental compilation

```ts
import { createNativeCompiler } from "./compiler/native.ts";
import { createNativeIncrementalCompiler } from "./compiler/native_incremental.ts";

const compiler = await createNativeCompiler({ threads: 1 });
const session = await createNativeIncrementalCompiler({ threads: 1 });
try {
  const analysis = await compiler.analyze(source);
  const artifact = await compiler.compile(source);
  const edited = await session.compile(changedSource); // artifact + cache stats
} finally {
  await Promise.all([session.dispose(), compiler.dispose()]);
}
```

The stateless API is a clean oracle. Incremental sessions retain declarations,
dependency groups, inferred interfaces, evaluated constants, and relocatable
Wasm function bodies. Only changed declarations cross the pipe; retained source
identities keep unchanged lambdas/local names stable. Cache keys encode complete
structure, including nominal operation identities and latent effect rows.
Reflection references are inference/const dependencies, not runtime calls.

Associated operators and generic effect selectors specialize before final
checking. Type and row substitutions use persistent indexes instead of scanning
the entire substitution history on every lookup. Each index retains replacement
order, including repeated bindings; occurs checks and traversal limits still
apply. Specializing a shared constant retains its generalized interfaces rather
than rechecking the enlarged module to recover them.

Independent specialization units run in weighted Bend batches. Each unit owns
its inference state and a disjoint sequence of generated identities; collecting
results in declaration order preserves deterministic output and diagnostics.
Constants with unresolved caller-dependent dispatch remain in a shared inference
scope. Checker branches inherit dependency interfaces for lookup and publish
only interfaces they produce, avoiding repeated merges of the shared
environment.

The specialization solver keeps an ordered list of unresolved operation and
associated requirements. After it selects an implementation, it filters the
previous list against the new choices and prepends requirements from newly
inferred definitions. Definitions remain in the same order as the full scan;
type arguments are resolved against the current substitution state when each
requirement is consumed. If the number of definitions shrinks unexpectedly, the
solver repeats the full scan.

Both clean builds and native sessions infer dependency-ready groups in balanced
Bend batches. Ordinarily, single-consumer dependency chains advance on their own
lane after each checked interface closes, without waiting for unrelated chains.
Recursive components still check separately and stay indivisible. Fan-outs and
joins remain separate frontiers: this is structured fork/join scheduling, not a
general ready queue or work stealing. Cache deltas and counters are lane-local
and publish only after a successful request. Wasm emission batches independent
cache misses. Small batches use sequential loops; completion order never chooses
diagnostic or output order. Const evaluation remains sequential because its fuel
budget is shared. The incremental planning cache retains the chain/frontier
schedule too; its existing key includes declaration order, dependency edges and
nominal type dependencies, so body-only edits do not rebuild that schedule.
Reused lowered declarations also retain their dependency/lambda scans and
scheduling cost estimates. Only changed declarations repeat these body walks;
whole-module type, operation, name, and lambda-identity validation still runs on
every revision. Scan failures remain values until their original diagnostic
position is reached. Prelude scans and canonical keys are still rebuilt.

Incremental inference-key preparation and codegen-key serialization also use
cost-balanced batches. Workers read an immutable frontier snapshot; cache hits,
misses, and failures are consumed in source order before publication. In broad
frontiers with sufficient estimated work per group, each worker proceeds
directly from key preparation to checking a cache miss, without a frontier-wide
preparation barrier. Singletons bypass the batch planner; two-to-four-group
frontiers prepare keys sequentially but still batch expensive checks. Cold
frontiers use a finer inference grain; sessions with prior group caches use a
coarser grain to amortize warm key checks. Key generation does not bypass
canonical comparison, dependency invalidation, or resource limits.

For plans with several frontiers, weakly connected dependency regions run
independently. Joins in one region do not stall another region's next frontier.
Genuine dependency joins remain within each region. Diagnostics retain original
job positions, and each region returns its own cache delta and counters for
success-only publication. Single-frontier plans keep their existing batching;
single-root graphs check their shared prefix first, then partition the remaining
graph without the already-satisfied dependency edges. Independent branches can
advance through their own frontiers; a join between unfinished branches still
keeps them in the same region. Connected multi-root graphs receive the same
treatment when the remaining work spans several frontiers. A final single
frontier keeps its batch, and already-independent regions never gain a shared
prefix barrier. Native sessions cache this schedule; it is still static
fork/join, not an arbitrary dependency-ready queue.

For a final module with at least eight singleton generated specialization
groups, the checker uses dependency-level frontiers. Within a frontier it checks
one representative of each equivalent singleton group, then attaches that
independently checked signature and interface to each follower's current body
and name. Equivalence requires the same source origin, complete body and
annotations, exact imported interfaces and nominal declarations. Local lambda,
block and return identities may differ by one uniform numeric offset; source
offsets and associated implementation identities must match exactly. The
operation catalog is shared within this final-checker call. Generic batch
callers that may mix catalogs keep independent checks. A failed representative,
comparison budget miss or unsuitable checked result runs the follower's normal
checker. Source certificates still take priority, and resulting failures and
certificates publish in original group order.

Sessions averaging at least 256 cached lowering-work units per declaration also
retain nominal-usage summaries. Changed declarations refresh in weighted
batches; an exact type-catalog key invalidates summaries when constructor
ownership changes. Small modules keep direct analysis and discard retained
summaries. Global validation, operation signatures, and graph keys retain their
original semantics. Prelude scans are not cached: a separate prelude-cache
wrapper regressed smaller workloads in performance controls.

Substantial codegen jobs also pipeline key serialization, cache lookup, and miss
compilation within each worker. Small jobs retain staged preparation and
balanced miss compilation. Publication remains ordered and transactional,
including when an earlier compile error competes with a later key error.

Linking resolves independent function bodies in weighted batches against one
immutable symbol catalog. Ordered collection preserves body order and the first
name, relocation, or entry-count error. Native output retains the sized Wasm
chunks instead of flattening a whole byte list. A single pass groups chunks into
coarse packing tasks; the existing batch executor packs independent groups, and
the native writer assembles their exact byte lengths into one response buffer.
Only the final response is padded, so the protocol and public artifacts remain
unchanged. Size and byte validation precede success-only cache publication.
Section planning, analysis encoding, and the final native buffer copy remain
serial. JS callers still receive flat Wasm bytes.

Large incremental diagnostic tables are resolved on demand from immutable,
declaration-local origins. At 8,192 origin entries or more, successful warm
edits no longer rebuild an entry for every reused syntax node. Smaller tables
retain eager indexing to avoid short-session latency regressions. Saved
diagnostics still refer to their own revision after later edits or disposal.

For raw-string clean builds, `threads` also caps a lazy, persistent Baba parser
worker pool. Sources below 32,768 UTF-16 code units parse locally; larger
sources split at conservative top-level boundaries with about 32,768 code units
per participant; each slice is validated by the full lexer and parser. The
caller parses one share alongside at most three workers, even at higher native
core counts. Each participant encodes Baba's compact tree directly into protocol
words, without building an object CST or Bend lists. Packed buffers transfer
back to the host, which merges their dictionaries in source order. Workers
perform lexing, layout, parsing, and compact encoding on raw-source slices. A
conservative top-level boundary scan and final dictionary merging/framing remain
serial; packed words are copied in bulk. The threshold uses source length, so
partitioning does not require whole-file lexing first. Ambiguous/rejected splits
use the canonical full parser for diagnostics; worker failures propagate and
close the pool. Dispose the compiler to terminate its workers. Already-parsed
source projects and incremental parsing retain their existing paths. The
synchronous JS reference compiler and the default one-worker native compiler do
not create this pool. The first large compilation overlaps worker startup with
caller-side parsing; warmed timings exclude startup.

At CPU request boundaries, the native transport clears drained Bend task queues
and resets their positions. Otherwise Bend 2.0.24's slot-major queues gradually
touch their full reserved region even when the live heap stays constant. This
version-specific cleanup asserts that every queue is empty, clears publication
bits as well as cursors, and leaves the compiler heap and session caches intact.
This cleanup does not apply to GPU runs. Run
`deno run --allow-all compiler/native_memory_bench.ts` on Linux for a
200-request artifact-parity and memory-mapping report (default eight threads).

Clean source lowering also splits declarations into cost-balanced fork trees. A
bounded CST-node count estimates each declaration once, and partitions retain
source order. Batches of at most four declarations stay serial; larger batches
use leaves of at most four declarations and 512 estimated nodes, or one
indivisible declaration. Incremental sessions use those trees for cache misses
only, keeping retained declarations out of the forked work. Cache publication
remains ordered and success-only; incremental lowering preserves its
first-source failure priority. Name collection completes first, and
clean-lowering joins preserve the serial lowerer's tail-first semantic
diagnostics and source-order output. Malformed declaration wrappers are
validated before those forks. Wasm runtime projection now shares codegen's
cost-balanced partitioner, with a separate 512-unit grain, sequential tiny
batches and first-entry error priority. Its bounded work estimate skips nested
lambda bodies, which have their own entries. Lowering, inference, projection and
codegen expose up to eight branches together; this spreads work across Bend
2.0.24's coarse CPU task lanes. Native request scanning consumes a single-owner
contiguous word buffer with flat loops; diagnostic formatting stays outside the
hot loops so Bend can optimize them. Per-request string dictionaries reduce
transport and allocation without bypassing Unicode validation or frame limits.
Raw-source CST materialization adds source offsets directly, avoiding a second
tree copy. Dependency-reference and ordinary reachability traversals use flat
work queues while preserving their original fuel and diagnostic ordering.

`just bench-native` compares JS with native 1-through-8-thread full builds,
edits, and cache hits. It verifies complete artifacts and executes the emitted
Wasm, then reports speedups against both JS and one native thread.
`just bench-grains` isolates inference, projection and codegen at those thread
counts, with matching JS jobs and a sequential reference at every cutoff. Its
optional third argument selects phases, e.g. `just bench-grains 64 3 prepare`.
The phase timings exclude parsing, transport and linking; they must not be
substituted for full-build speedups. See
[the concurrency review](CONCURRENCY.md) for current measurements, changes and
remaining limits, and [the earlier measurements](PERFORMANCE.md) for history.

`just bench-cpu` is the Linux physical-core benchmark. It requires `taskset`,
`/proc`, sysfs CPU topology, and eight eligible physical cores by default. Each
sample starts a fresh pinned host/native process, performs two warmups, and
records full-build, body-edit and unchanged-request timings. JS reference
artifacts are compiled and executed in separate processes, then deserialized
before timing; native hosts never load the JS compiler or its JIT/GC work.
Balanced 64 also runs 50 identical preencoded requests in one retained native
process at one and eight workers, with fresh warmed controls at requests 10, 30
and 50. Startup, verification, Wasm execution and CPU/RSS inspection are outside
timed regions. It does not reserve cores from other desktop work or recycle
retained processes.

```sh
just bench-cpu 9 build/cpu-scaling.json . 1,2,3,4,5,6,7,8
# Interleave snapshots, each with its matching frontend, protocol and executable:
just bench-cpu 9 build/cpu-scaling-paired.json .,build/cpu-baseline 1,8
# Resume an interrupted sweep only with matching sources/builds and settings:
deno run --allow-all compiler/cpu_scaling_bench.ts --resume build/cpu-scaling-paired.json .,build/cpu-baseline 9 1,8
```

Snapshot transports must expose the read-only `NativeProcess.pid` diagnostic
getter. Baselines must be saved before rebuilding; the command builds only the
current project. Raw reports include source/Wasm and executable hashes, CPU
affinity, native process CPU ticks and RSS. Native full/reuse rows also record
host CPU ticks and RSS, including parser workers. The Staggered 64 fixture
places expensive declarations at different depths in independent dependency
chains to expose inference barriers. Full-build native artifacts must equal JS;
incremental Wasm/signatures must equal clean builds, while unchanged requests
must equal the previous complete session artifact. Session-local closure
identities and offsets are intentionally not compared with clean builds.
Incremental rows include `base_revision_ms` and `base_cache` for the preceding
revision; the first warmup row records the first session compile separately from
warm body-edit latency.

For separate phase diagnostics:

```sh
BEND_NO_TELEMETRY=1 bend compiler/native_main.bend -o build/cpu-phases.c
deno run --allow-read --allow-write compiler/cpu_scaling_trace.ts build/cpu-phases.c build/cpu-phases-trace.c build/phase-events
clang -std=c11 -O3 build/cpu-phases-trace.c -lpthread -lm -o build/cpu-phases-trace
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-phases.json . 3 1,8 balanced_64,clustered_64 full build/cpu-phases-trace
```

The injector requires unique named phase boundaries and fails on changed
generated structure. The trace executable is the seventh argument to the
benchmark driver; never use instrumented timings as the production headline
benchmark. Logs are flushed before the response payload is written, so immediate
host disposal cannot lose the last trace. The final `send` interval measures
frame preparation and header writing, not payload writing or log-file IO.

Changed source undergoes a conservative declaration-boundary scan. After the
first edit warms the fragment cache, unchanged raw fragments reuse validated
lexing/layout and token indexes; only changed fragments are lexed again. The
cache retains one syntactically valid revision, not the edit history. Unchanged
declaration token sequences also reuse Baba CST islands and their stable
identities, including across trivia edits. Ambiguous boundaries and rejected
fragments fall back to the complete lexer/parser for exact diagnostics. The
initial revision always uses the complete parser. Exact successful revisions
also reuse a privately retained artifact without IPC. Returned artifacts are
independent copies, and changing the operation or const budget prevents that
shortcut. Stats distinguish parsed/reused islands, full-parser fallbacks, result
reuse, and `characters_lexed`/`characters_reused` (UTF-16 code units; fallback
retries count their repeated work). `parsed_ms` includes the complete
incremental frontend, including normalization and source-origin remapping.

Failed edits do not publish partial state or advance the acknowledged revision.
Const caches include entering fuel and transitive source dependencies. Link-time
relocation is repeated against the current catalog; cached code contains no live
table indices or runtime pointers. The JS worker-pool implementation remains a
separate reference with the same compiler semantics.

The binary native protocol is version **11**. Its bounded little-endian frames
contain at most 16M words (64 MiB), per-request dictionaries of Unicode scalar
strings, and 48-bit Nats. CST kind/field/text values reference dictionary IDs;
IDs are assigned in first-seen preorder across all trees in the request. The
native decoder owns a contiguous word buffer and checks every access against the
valid frame length, including dictionary IDs and allocation counts. Rebuild the
executable with the host: older protocol versions are not accepted. Stdout is
reserved for frames; stderr carries process diagnostics. Framing or process
failures are fatal; checked language diagnostics leave a session usable. No
native error triggers a silent JS fallback.

## Source modules

The CLI loads relative file imports and the explicit `std/` directory mapping.
Imports precede declarations; `.blot` may be omitted. Both namespace and named
imports work, including aliases:

```blot
import * as array from "std/array"
import { Point as Position, coordinate } from "./geometry"
const answer = fn () => array.fold_left U32.add 0 [10, 20, 12]
```

Programmatic callers use `loadSourceProject(entry, { imports })` from
[source_project.ts](source_project.ts), then pass that project to either
compiler's `analyze` or `compile` method. The loader reads each dependency once,
diagnoses cycles, and retains per-file diagnostic locations. Bend resolves
public declarations, module scopes, nominal type/effect identities, and
qualified type annotations. Top-level declarations are importable by default.
Only entry-module bindings with concrete guest ABI-compatible types become Wasm
exports. Generic and structural helpers remain importable Blot values. Importing
a type does not implicitly import constructors with different names. Imported
operator functions need a local fixity declaration; prelude fixities are
available in every module.

The loader overlaps up to four dependency-file reads while keeping parsing,
cycle diagnostics and module order deterministic. Bend prepares imported name
scopes in order, then lowers independent module bodies in weighted batches;
single-module projects bypass the batch planner. Large value and nominal-type
graphs also run their two SCC passes concurrently. The concurrency report
records both multicore gains and the measured single-core tradeoffs. For
prepared-project benchmarks, use `compiler/project_concurrency_bench.ts`;
`nominal_256` in the standard CPU benchmark covers large type graphs.

For repeated project edits, use `createNativeProjectCompiler` from
[native_project.ts](native_project.ts):

```ts
const project = await createNativeProjectCompiler({
  imports: { "std/": new URL("./std/", import.meta.url) },
});
try {
  const { artifact, stats } = await project.compile("./src/main.blot");
} finally {
  await project.dispose();
}
```

A project session rereads the import graph, reuses unchanged parsed modules,
assigns stable declaration identities, and transmits changed declaration trees.
Bend retains successful lowering, specialization, checking, constant evaluation
and code generation work. Scope or schema changes invalidate conservatively;
failed edits preserve the acknowledged native revision. An unchanged normalized
project and const budget reuse a private result without native IPC. Returned
artifacts are independent copies. `stats` reports declaration, checking,
constant and code reuse plus loading/preparation and total request times.
Checking counts describe the final group cache; specialization can still run
inference, so a high hit count does not imply a proportionate latency reduction.
See the [current gdev measurements](COLD_COMPILE_RESULTS.md) for startup and
edit tradeoffs. Gdev currently uses the faster stateless path for changed
source, retaining parsed modules and its last successful artifact in the host.

The project API recycles its native process after 16 native analyze/compile
attempts by default (`maxRevisions` sets another positive limit). This bounds
per-process growth from the [documented Bend boxing leak](MEMORY.md). An
unchanged or trivia-only result reuses the last successful artifact locally and
does not consume a revision. After recycling, the next native request resends
all declarations; `stats.session_restarted` identifies that request. Failed
native edits count toward the limit, while the previous successful result stays
available for recovery.

The stateless project API remains available as a clean-build oracle. Passing
imports to a raw string compiler is an error, not an implicit filesystem read or
ignored declaration.

## Executable language

`deno task blot guide` prints the [compact language guide](guide.md), including
complete checked examples. It does not start or build the native compiler.

- Nominal `type ... is data` declarations with nullary/unary constructors and
  nested patterns. Types and effects take one argument pattern per stage:
  `[left, right]`, `(left, right)`, and `{ head, tail }` can bind several type
  values. Currying requires `=> type`, and partial constructors survive
  grouping. Free lowercase annotation names are inferred within their
  declaration.
- Top-level functions are ordinary `const name = fn ...` or `let name = fn ...`
  bindings. Every top-level declaration is public; concrete entry values that
  fit the guest ABI become Wasm exports. `const` evaluates at compile time;
  `let` initializes once at runtime when the module starts.
- Named record constructors, such as
  `type Vec2 is data = Vec2 { x: F32, y: F32 }`. Construction requires every
  field exactly once; shorthand `{ x, y }` uses lexical bindings. Fields
  evaluate once in written order, even when reordered relative to the
  declaration. Named patterns can reorder or omit fields, with omitted fields
  acting as wildcards. Dot access reads fields shared by every constructor of
  the type. Zero/one/many fields lower to ordinary nullary/unary/tuple
  constructor payloads, not a separate runtime record kind.
- Heterogeneous tuples `(42, True)` with annotations `(U32, Bool)` and static
  `@product.get value 0` projection. Parenthesized single values stay ordinary
  values; Unit stays `()`. Projection needs a known tuple shape, from a value or
  annotation. Tuple patterns infer the shape from their arity and nest inside
  records and algebraic constructors. Matching preserves correlations between
  tuple fields as well as between multiple scrutinees.
- Homogeneous immutable arrays, including empty/nested literals and `Array T`
  annotations, direct indexing with `values[index]`, and prelude members
  `.length`, `.is_empty`, `.get(index)`, and `.set(index)(replacement)`.
  `@array.fill count value`, `@array.generate count generator`, `@array.length`,
  `@array.get`, and `@array.set` are generic memory primitives;
  [std/array.blot](../std/array.blot) supplies checked access, construction,
  folds, and short-circuit predicates in source. Fills evaluate their value once
  and preserve immutable sharing. Generation allocates once and calls a pure
  `U32 -> T` function for each index in ascending order; zero skips the
  callback. Both reject counts that exceed the 16 MiB runtime arena before
  computing an allocation size.
- Curried named functions/lambdas, immutable lexical capture, rank-1 inference,
  pure/closed-effect annotations, and inferred higher-order effect rows.
- `case value of` and `case a, b, c of`; every row has the same arity. Inputs
  evaluate once left-to-right; coverage checks combinations, not columns
  independently. Duplicate bindings in one row are rejected.
- `if let pattern = value:`, irrefutable bindings, and
  `let pattern = value else:` with an exiting failure suite.
- `do:` expressions and nearest-block `return`. Falling through yields Unit.
  `let` requires a pure RHS; `use name <- expression` permits effects.
  `use expression` is a discard binding, not a handler or boxed action.
- Whole-binding shadowing with `name := expression`. The target must already be
  a local or parameter; `self` names its old value only within the RHS. The new
  binding is pure and can change type; previous aliases and captures keep their
  original values. Field/index paths such as
  `grid.rows[row][column] := self + 1` rebuild the local root, with `self` bound
  to the selected old leaf.
- Closed source operations, provider values, `do provider:`, and const effect
  descriptors. See [the full contract](effects-and-io.md).
- Unit, Bool, U32, and F32 scalar values. U32 arithmetic wraps at 32 bits.
  Decimal/hex separators work; overflowing literals fail. F32 literals round
  directly to binary32 ties-to-even, including subnormals. Arithmetic can yield
  infinity/NaN; no implicit U32/F32 conversion. Prefix `-` is F32 negation;
  parenthesize negative call arguments.
- Generic `@panic "message"` produces Never and traps in Wasm; const evaluation
  reports its message as a diagnostic. It supplies no IO authority.
- Explicit host callbacks with a sealed `Foreign` effect, scalar signatures,
  opaque invocation-scoped references, and a versioned generic adapter. See
  [guest ABI 2](guest-abi.md) and
  [the executable example](../examples/host_io.blot).

## Prelude and operators

Numeric operators use the prelude's generic `add`, `sub`, `mul`, `div`, and
comparison functions. Their `@type.call "member" left right` expressions resolve
against the operands' owning types at compile time, with a compatible left
implementation taking precedence over the right. Arguments are never swapped.
Generic callers are specialized before ordinary checking, constant evaluation,
and code generation; unresolved dispatch cannot reach Wasm. See
[associated dispatch](../std/README.md#u32-and-operators) for examples.

[std/prelude.blot](../std/prelude.blot) is ordinary source, loaded once per
frontend session. `{ prelude: "none" }` selects a freestanding module. Prelude
exports become visible source names, but only root exports become Wasm exports.
Direct qualified calls such as `Maybe.map` resolve to that named function.
`@type.call` requests associated dispatch explicitly.

Receiver syntax resolves from the receiver's type: `tail.contains(x)` applies an
ordinary associated function, and `tail.contains` partially applies it. Lookup
does not fall back to the argument's type. Named record fields use the same dot
syntax; a field and associated function sharing a name are ambiguous.

Symbolic operators have source fixity declarations; backticks use ordinary
functions, e.g. `a \`combine\` b`. No operator implies a game-specific
primitive. Higher-order prelude functions propagate callback effects. See
[the prelude reference](../std/README.md).

Low-precedence application is also source-defined: `infixr 0 ($) = apply`, where
`apply function value` calls `function value`. Thus `f $ g $ x` means `f (g x)`.
Infix RHSs can be lambdas, blocks or matches. `$` retains eager evaluation and
inferred effects; `return $ value` remains separate resolver forwarding syntax.
Plain `do:` functions already fall through to Unit without an explicit
`return ()`; expression-bodied functions return their expression.

## Evaluation and Wasm representation

Const evaluation has an explicit shared step budget. Handled operations use the
same scoped-provider rules as runtime; unhandled operations fail. Closed effect
descriptors are opaque const values, not numeric runtime IDs. Ordinary helper
functions may calculate with them during const evaluation. Runtime reachability
omits const-only helpers; a live descriptor value/operation reports
`backend_const_only`.

Internal functions take closure environment, argument, and provider chain.
Provider frames are immutable and lexical, so early returns cannot leak a
binding. Closures capture locals, not active providers: invoking an escaped
closure uses the caller's provider scope. A provider implementation sees the
outer chain, excluding the selected provider and younger frames.

Export wrappers accept Unit/Bool/U32/F32, Array U32/F32, or one scalar callback
with exactly `! {Foreign}`, and return scalars or numeric arrays. The adapter
copies typed-array inputs and outputs so hosts can retain state across reloads.
Callback parameters use `externref` and signature-specific `blot:host/1`
imports. Scalar-only artifacts stay import-free. Every module describes its
exports in `blot:abi`; the adapter validates this manifest and scopes supplied
callbacks to the current invocation. Ordinary unhandled source operations still
fail instead of acquiring ambient IO.

Arrays have a length header and contiguous machine-word elements; tuples have
fixed-size contiguous fields. Nested values and closures occupy reference lanes,
not recursive list nodes. Elements evaluate once left-to-right. Indexes are
checked unsigned U32 values; invalid const accesses report `array_bounds`, and
runtime accesses trap, including inside range guards. The prelude's checked
`Array.get` and `Array.set` return `Maybe` instead.

Updates preserve existing aliases. The ownership pass scans each instruction job
for consumed local allocations and can reuse their storage, including a single
array carried through a loop. Parameters, captures, module values, and projected
arrays remain conservative copy cases. Shared or unknown storage is copied in
full, so repeated updates can still have quadratic copying cost. Const updates
always copy and charge one extra step per copied element. Array size arithmetic
is checked before allocation; the private arena is bounded to 16 MiB.

Value patterns use `^name` or `^module.name` to compare a `U32` or `Bool`
against an existing constant, parameter, or lexical binding. Pins introduce no
bindings; all references resolve in the surrounding scope before the pattern's
bindings are added. They work in case rows, nested constructor/record/tuple
patterns, `if let`, and `let … else`. Coverage treats pins as refutable,
including constant references. Inference checks the referenced type after
solving the declaration; unconstrained pins need a scalar annotation. Both
evaluation and Wasm matching short-circuit failed patterns. Pins perform scalar
equality without allocating.

Internal closures and data values stay inside the module. Multi-value matches
use locals rather than heap-allocated tuples. Each invocation resets its arena;
the adapter rejects same-instance reentry and callback/ADT return values cannot
escape as persistent handles.

Wasm uses binary format version 1, also used by newer Wasm standards; a
different binary header is not how Wasm 3.0 features are selected. The current
emitter does not yet require newer proposals, SIMD, or Wasm-GC.

## Deliberate limits

Array patterns, spread syntax, destructuring function parameters, general
Text/F64, SIMD, inferred generic effect-family labels in explicit polymorphic
rows, demand parameters, type-valued consts, and resumptions are not
implemented. `do monad Maybe:`/`return $` remain design syntax, not implemented
monad resolution. An unconstrained provider parameter cannot infer an unknown
operation identity in this first closed-label slice.

[Controlled host IO](effects-and-io.md#controlled-host-io) uses explicit
callbacks and the [guest adapter](guest-abi.md). Generic libraries can declare
`type State a is effect` and call its operations normally. Their type arguments
are inferred from arguments and result context, then resolved to closed effects
during monomorphization. `@effect.run` supplies scoped state handlers. Constant
source builders can compose their storage and scoped access functions. The
removed compiler-coupled sandbox is preserved only as a
[prototype reference](../case-study/ecs/prototype/README.md).

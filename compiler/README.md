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
for each installed Bend version downloads five upstream loader files from that
version's release tag into `generated/compiler/bend-<version>/`; subsequent
builds reuse them offline. Release tags must be available upstream for JS
builds. The JS build also emits `generated/compiler/native_session.js` for
direct regression tests of the native session's pure cache-planning logic.

The build uses the latest released Bend's generated C and JavaScript without
output patches. Clang compiles the emitted C directly, and the upstream loader's
JavaScript is saved unchanged. Host code handles the JavaScript data boundary.
Suspected upstream bugs and performance limitations are recorded in
[BUGS.md](../BUGS.md) for review before filing an issue.

The active [compile-speed plan](../PLAN.md) prioritizes a small paired
performance experiment on gdev's actual cold and body-edit paths before further
M3 expansion. The [experiment results](COMPILE_SPEED_RESULTS.md) include the
reusable benchmark command, current baseline, and the limits of each
measurement.

Historical [cold-compilation results](COLD_COMPILE_RESULTS.md) include native
output patches that have since been removed; those timings do not describe the
current build. The [scaling plan](COLD_COMPILE_PLAN.md) records the remaining
gap to 500 ms. The [type-system redesign study](TYPE_SYSTEM_REDESIGN_STUDY.md)
investigates the broader changes needed for a 100–200 ms source-to-Wasm target.
The [retained-checking implementation](TYPED_CORE_IMPLEMENTATION.md) records the

implemented reuse boundaries, correctness checks, and measured limits. The
[allocation and checking follow-up](TYPE_KERNEL_IMPLEMENTATION.md) records the
former native kernels alongside source-level improvements. Bend 2.0.24 passes
the ownership regression that required an isolated emitter patch on 2.0.5, so
that obsolete patch has been removed. The build still compiles and runs
[the regression](native_backend_regression.bend) at 1 and 4 threads before
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
  const { bytes } = await compiler.compile(source, { analysis: false });
  const edited = await session.compile(changedSource); // artifact + cache stats
} finally {
  await Promise.all([session.dispose(), compiler.dispose()]);
}
```

`compile` returns the Wasm bytes and the analysis (functions, constants,
remaining const steps). With `analysis: false` it returns only `{ bytes }`: the
Wasm module carries its guest ABI in the `blot:abi` section, so
`instantiateGuest` needs nothing else. Wasm-only compiles run the same pipeline
and session caches as full compiles and produce identical bytes; the native side
just skips encoding the analysis and the host skips decoding it. Every compiler
(`createNativeCompiler`, the native incremental and project sessions, and the
JavaScript references) accepts the option. Runtimes that only instantiate guests
should use it.

### Scheduling

Desktop schedulers often demote the Deno process that launches `blotc`. For
example, ananicy-cpp's default rule
`/etc/ananicy.d/00-default/Development & Programming/deno.rules` gives every
`deno` process the `BG_CPUIO` type (SCHED_IDLE, nice 16, idle IO class) and
reapplies it every 15 s. A child inherits all three, so a ~3 s compile could
take 10-15 s on a loaded machine. On Linux, `blotc` therefore restores normal
scheduling at startup, before the Bend runtime creates its worker threads. If a
thread runs under SCHED_IDLE, or under SCHED_OTHER/SCHED_BATCH with a positive
nice value, `blotc` switches it to SCHED_OTHER with nice 0 and best-effort IO
priority 4. A thread in the idle IO class also gets best-effort IO priority 4.
Policy, nice and IO priority are per thread on Linux. `blotc` resets every
existing task, and the worker threads it creates later inherit the result.
ananicy matches process names, so it does not demote `blotc` itself later. This
is best effort. Leaving SCHED_IDLE or lowering the nice value needs
`RLIMIT_NICE` of at least 20 (`ulimit -e`); on EPERM `blotc` keeps the inherited
setting. Real-time policies, SCHED_BATCH at nice 0 and negative nice values are
left alone. Pass `--inherit-priority` to `blotc`, or `priority: "inherit"` to
`createNativeCompiler` and the native sessions, to keep the launcher's
scheduling. `native_priority.test.ts` launches `blotc` under `chrt --idle 0`,
`nice -n 16` and `ionice -c 3` and checks every thread after the handshake and
after a compile. Some harnesses keep rewriting the scheduling of every
descendant thread; for example, a wrapper that forces SCHED_BATCH would hide
`blotc`'s own choice. Each test `blotc` therefore runs outside the test's
process tree: `setsid --fork` orphans a shell that keeps the test's stdin and
stdout and reports the compiler's pid and exit status. A launch that still shows
a harness's SCHED_BATCH nice 0 is retried twice, then fails. The checks are
skipped only when `ps`, `setsid`, `chrt`, `nice` or `ionice` is missing, or when
`RLIMIT_NICE` is below 20.

The stateless API is a clean oracle. Incremental sessions retain declarations,
dependency groups, inferred interfaces, evaluated constants, and relocatable
Wasm function bodies. Only changed declarations cross the pipe; retained source
identities keep unchanged lambdas/local names stable. Cache keys encode complete
structure, including nominal operation identities and latent effect rows.
Reflection references are inference/const dependencies, not runtime calls.

Associated operators and generic effect selectors specialize before final
checking. Before any declaration is templated,
[concrete dispatch resolution](dispatch_resolution.bend) removes the dispatch
that does not depend on a caller. Saturated operator calls (`a + b` calls the
prelude forwarder `add`) are first inlined as the forwarder's `@type.call` site,
keeping the operator's source offset as the site's identity; that is the call
specialization would build anyway. The initial shape check then reports, for
each declaration group it infers, every associated, receiver-method and field
requirement with its types in the group's own variable numbering. A per-group
solver selects a site once its operands (binary dispatch) are closed, i.e. their
types contain no inference, generalized or row variable, or once its receiver's
nominal head is known (member and field access select from the owner type
alone). Selection uses specialization's own functions and is validated by the
same unification against the requirement's result and effect row; the solver
keeps those unifications, so a result one selection fixes closes the
requirements that consume it in the same pass. Every such selection is what
every specialization of the declaration would choose, so the site is rewritten
into exactly the call specialization would substitute. Ambiguous members,
field/method clashes, missing members or fields, type identity and typed-state
requests, linked-schema methods and failed validations stay deferred, so
specialization still owns their diagnostics. A rewrite that refines a rewritten
declaration's interface is checked again: groups whose declarations and imported
interfaces are unchanged are retained from certificates, and requirements that
the more precise interfaces close are resolved in the next round (at most 32). A
rewrite that leaves every interface and every local `let` scheme unchanged needs
no further check; the final check re-infers only the rewritten groups. Inference
records, per `let`, the variables its generalization quantified (or whose rows
its scheme closed) that a deferred requirement of the bound value mentions. A
round whose solver binds such a variable, or binds a variable of the group to a
type that mentions one, would change what the `let` means at its uses (for
example `let helper = fn (x: U32) => x + 1` stops being generic in its result),
so it is checked again like an interface refinement. Only a fresh variable of a
selected implementation's instance may name one, which is how the rewritten
direct call instantiates inside the `let`. The original source is checked before
inlining or pruning, so a source error is reported directly after one check.
Successful source checking supplies the checked module and certificates for
resolution; a failed transformed round returns to that checked source without
checking it again. Within that compilation, unchanged groups retain their
checked result together with the complete dispatch requirements from the same
inference. Reuse requires exact declarations, ordered imports, nominal types,
and the full ordered operation catalog. A rejected witness is inferred again;
ordinary certificates can only retain source-ready groups. Incremental sessions
retain source-ready first-pass certificates from successful revisions for exact
group reuse on later revisions; groups with deferred dispatch are inferred again
so their resolution needs are collected. Ready certificates also reach the final
check behind the session's group cache. Native session
`groups_checked`/`groups_reused` count this final pass, not the earlier source
inference: a changed, ready source group may be freshly inferred there and then
counted as reused here. The source-pass audit probe separately verifies exact
retention and invalidation. A declaration without remaining deferred dispatch is
no longer a template seed: a helper such as
`leaf = fn value => @u32.add value 1 + 0` compiles once instead of once per
caller path, and `Array.get`'s bounds comparison no longer clones `Array.get` at
every use. Dispatch on operand types a caller supplies is still specialized per
reference.

Field access uses one shared accessor per receiver nominal type and field,
`$member[<owner>].<field>` (reads) and `$member.set[<owner>].<field>` (updates),
instead of one per access site. Its body depends only on the type's constructors
and its independently checked interface is generic in the type's arguments, so
resolution and every specialization unit reuse the same function; parallel units
that both create it keep the first copy in source order. An accessor that fails
its independent check falls back to the per-site `$member[<n>]` helper, which
reports the diagnostic exactly as before.

Read-only string indexes select a child as data and carry the key and its
remaining suffix through one Bend tail loop. This avoids allocating branch
closures and keeps native and JavaScript lookup on the same implementation. Name
equality retains its owning string roots while separate cursors traverse their
characters, enabling borrowed reads in the full native compiler. Numeric
Patricia lookup also uses one tail loop while preserving prefix checks, and
string suffixes are left untouched when the next branch inspects another bit of
the same character. The [native gdev measurements](COMPILE_SPEED_RESULTS.md)
record cold compilation falling from 126.9 to 62.3 seconds across three Bend
2.0.32 experiments, with identical Wasm. The latest batch improves its own
control from 75.8 to 62.3 seconds; peak native memory remains about 279 MiB. A
scheduler experiment that exposed more inner parallelism was parked after
slowing the actual game.

Dependency and definition-predicate lookups stop at the first match. Bend's
`Bool.pick` evaluates its result arguments eagerly, so recursive searches use an
explicit match state instead of passing a recursive call as an alternative.
Operation merging skips a retained catalog prefix before falling back to the
ordinary ordered merge. Together these changes improve a fresh matched cold
control from 41.37 to 39.98 seconds. Body-edit timing is mixed and peak memory
remains about 280 MiB; the overnight change from the earlier batch is not
counted as an improvement from these changes.

Type and row substitutions use persistent indexes instead of scanning the entire
substitution history on every lookup. Each index retains replacement order,
including repeated bindings; occurs checks and traversal limits still apply.
Specializing a shared constant retains its generalized interfaces rather than
rechecking the enlarged module to recover them.

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

For separate phase diagnostics, attach GDB to the native process reported by
`NativeProcess.pid` and sample stacks or set breakpoints on named Bend wrappers:

```sh
gdb --quiet generated/compiler/blotc -p <native-pid>
```

For example, `thread apply all bt 16` shows active worker stacks, and
`break WL_FID_MONOMORPH_SHARE_CONSTANTS` stops at shared-constant preparation.
Disable a breakpoint after its first hit when recording first phase entries. Use
the original executable and generated output unchanged. Debugger pauses and
stack samples belong in separate diagnostic runs; keep them out of latency
comparisons. Saved gdev diagnostics and their limitations are described in
[COMPILE_SPEED_RESULTS.md](COMPILE_SPEED_RESULTS.md).

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

The binary native protocol is version **12**. Its bounded little-endian frames
contain at most 16M words (64 MiB), per-request dictionaries of Unicode scalar
strings, and 48-bit Nats. CST kind/field/text values reference dictionary IDs;
IDs are assigned in first-seen preorder across all trees in the request. The
native decoder owns a contiguous word buffer and checks every access against the
valid frame length, including dictionary IDs and allocation counts. Rebuild the
executable with the host: older protocol versions are not accepted. Stdout is
reserved for frames; stderr carries process diagnostics. Framing or process
failures are fatal; checked language diagnostics leave a session usable. No
native error triggers a silent JS fallback. Request opcodes are 0/1 stateless
analyze/compile, 2 open session, 3/4 session analyze/compile, 5/6 declaration
patches, and 7/8/9 emit (stateless, session, patch). Emit is the Wasm-only
compile behind `analysis: false`. Response kinds are 0 diagnostic, 1 analysis, 2
artifact (analysis and Wasm), 3 opened, 4 cached (eight counters and an inner
kind 1, 2 or 5), and 5 Wasm only.

## Entry declarations and dead-code elimination

`entry const` and `entry let` mark host entrypoints:

```blot
entry const create = fn () => host.create sandbox state_schema ()
entry const frame = fn (packet: Array F32) => host.frame sandbox state_schema packet
entry const state_schema: U32 = 2
```

`entry` is a contextual keyword. The grammar accepts an optional identifier
before `const` or `let` at the start of a top-level declaration (after any
`#[...]` tags), and lowering accepts only `entry` there (`unknown_modifier`
otherwise). Everywhere else `entry` is an ordinary identifier: a parameter, a
`let` or pattern binding, a record field or a declaration name. The editor
grammar highlights it only as the modifier of a `const`/`let` on the same line.

An expression tag `#[f args]` decorates a value declaration as `(f args) value`.
Several tags compose nearest first, and an annotation constrains the decorated
result. Tags on `const` run at compile time; tags on `let` run at startup. Their
expression dependencies enter reachability and incremental cache keys.

Binding annotations may carry a contextual `where { ... }` clause after the
complete type and effect row. It records associated, receiver, field, update,
operation, type-representation, and effect-representation requirements on a
rank-one binding. Local `let` supports the same form; parameter annotations do
not. Open effect rows use `! {Operation, ... | e}` or `! {| e}` with a row
variable scoped to the binding. Type and row variables share names but cannot
use the same name at both kinds. The annotation and clause describe the value
after all expression tags have run. `where` remains an ordinary identifier
outside the clause boundary. Open rows currently require concrete operation
labels; symbolic generic labels such as `State a` receive
`unsupported_polymorphic_effect_label` at the source clause.

The raw core `analyze`/`compile` API performs type checking but does not run
source evidence selection. It rejects a core `QualifiedExpr` with nonempty
predicates as `unspecialized_qualified` before constant evaluation; use the
source compiler for such bindings. An empty qualification wrapper is allowed.

Only the entry module reaches the host, so `entry` in any other module, the
prelude included, is `entry_outside_entry_module`. `entry` never affects Blot
visibility: every declaration of every module stays importable exactly as
before, and an entry declaration is referenced like any other constant. A module
that declares entries is therefore an application, not a library: a second build
that imports it reports the same diagnostic, so share code through a library
module instead.

Exactly the entry module's entry declarations become Wasm exports, under their
own names; several are allowed and nothing is exported implicitly. Lowering sets
the declaration's `exported` flag from the modifier and nothing else sets it.
Export selection keeps an entry only when its final type fits the guest ABI, and
the final check then verifies every entry: an entry that does not fit (for
example a generic function, an `Array` constant or an unhandled effect) is
`entry_type`, or `entry_let_type` for a runtime-initialized `entry let` value
(the ABI exports runtime values only as scalar globals or functions). Analysis
reports these too. A Wasm build (`compile` and the Wasm-only `emit`) without any
entry declaration is `no_entry`; `analyze` accepts it, still checks every
declaration and reports nothing reachable.

The entries are also the only dead-code roots. Every declaration passes the
initial check, so type errors in unused code are still reported. Right after
that check (the first round of
[concrete dispatch resolution](dispatch_resolution.bend), or the specialization
fallbacks when resolution does not apply),
[entry_points.bend](entry_points.bend) computes the declarations the entries
reach over the lowered dependency graph: function, constant and `let`
references, value-pattern pins and reflection targets. A deferred dispatch site
cannot know its implementation before specialization, so a reachable site with
member `m` keeps every declared `<owner>.m`, where the owner is a data type or
builtin nominal prefix exactly as specialization names implementations. Nominal
type and operation metadata stays available for checking and constructor layout.
The backend emits constructor-function and operation wrappers only when runtime
code or retained constant values reach them. Declarations are scanned in
parallel Bend batches of 64; the walk itself is one flat work queue. Resolution
rounds, specialization, the final check, const evaluation, runtime
initialization and code generation then see only reachable declarations, and the
initial check's certificates, shapes and group requirements are pruned alike.
When nothing reachable needs specialization, the final check retains every group
from those certificates, so the code is still inferred once. Consequently an
unreachable constant is never evaluated (a panic or an exhausted step budget
there no longer fails the build), an unreachable `let` initializer never runs at
startup, and diagnostics that specialization owns, such as `missing_associated`
for `True + False`, appear only in reachable code. The analysis lists reachable
declarations only.

Native sessions and project sessions key lowered declarations by their complete
syntax, so adding or removing `entry` invalidates exactly that declaration and
the specialization, check, constant and code caches that depend on its export
flag.

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
qualified type annotations. Top-level declarations are importable by default,
entry declarations included. Only the entry module's `entry const` and
`entry let` declarations become Wasm exports (see
[entry declarations](#entry-declarations-and-dead-code-elimination)). Importing
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
  bindings. Every top-level declaration is public; `entry const` and `entry let`
  declarations of the entry module are its Wasm exports. `const` evaluates at
  compile time; `let` initializes once at runtime when the module starts, when
  an entry reaches it.
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
  callback. Both reject counts whose length header and payload overflow a Wasm32
  byte count before computing an allocation size. Compile-time arrays retain the
  separate 16 MiB bootstrap limit.
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
- Explicit host callbacks with a sealed `Foreign` effect, scalar or
  numeric-array signatures, opaque invocation-scoped references, and a versioned
  generic adapter. Async capabilities can suspend a running guest while
  retaining its locals and exclusive invocation ownership. See
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
declarations become visible source names; only the root module's entry
declarations become Wasm exports, and only the prelude declarations they reach
are compiled. Direct qualified calls such as `Maybe.map` resolve to that named
function. `@type.call` requests associated dispatch explicitly.

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

Before instruction-job caching, a bounded saturation pass expands small known
functions whose leading bodies are literal curried lambdas when every argument
is supplied. Arguments evaluate once, left to right, into fresh temporaries
before parameter bindings are introduced. This removes intermediate closures for
ordinary arithmetic operators and other small helpers. Dynamic calls, partial
applications, and functions doing work between lambda stages retain their
curried behavior. Known unary function references use the existing direct entry.
Expanded bodies participate in the caller's cache key; recursion, expansion
size, and loop movement are conservatively restricted.

Export wrappers accept Unit/Bool/U32/F32, Array U32/F32, or one
scalar/numeric-array callback with exactly `! {Foreign}`, and return scalars or
numeric arrays. The adapter copies typed-array inputs and outputs so hosts can
retain state across reloads. Callback parameters use `externref` and
signature-specific `blot:host/1` imports. Artifacts without host callbacks stay
import-free. Every module describes its exports in `blot:abi`; the adapter
validates this manifest and scopes supplied callbacks to the current invocation.
Ordinary unhandled source operations still fail instead of acquiring ambient IO.

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
is checked before allocation; the private arena grows on demand through the
Wasm32 address space. Failed growth traps without changing its cursor.

Eligible `for ever` loops reclaim arbitrary nested carry graphs every fourth
backedge with a nonmoving conservative collector. Each loop activation owns its
counter, so nested loops cannot delay an outer loop indefinitely. Collection
amortizes tracing work but adds latency to collection iterations and retains up
to four iterations of temporary allocations. Allocation headers and an
exact-start bitmap identify blocks; marking preserves sharing and scans pinned
pre-loop objects, then sweeping recycles unreachable blocks into size-class
bins. No graph is serialized or copied during collection. Scalars that happen to
equal an object address may retain extra objects, but are never rewritten.
Dynamic blocks start at or above 64 KiB to avoid collisions with common small
integer IDs; static data can still occupy the first page. The block-start bitmap
is cached across free-list reuse. Fresh bump allocation invalidates it,
including the first such allocation after an arena reset; collection then
rebuilds it. Effect-provider escape exclusions still apply. The readable runtime
is `arena_runtime.wat`; `deno run -A scripts/generate_arena_runtime.ts`
regenerates its relocatable Bend encoding (WABT is only required for
regeneration).

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

# Compiler core

The compiler is written in Bend 2.0.5 and compiled to a native CPU executable.
Deno supplies I/O, layout/source positions, and Baba's field-labelled CST, then
sends it to a persistent subprocess. Name resolution, operator precedence,
inference, const evaluation, closure conversion, and Wasm emission are Bend
code. There is no JavaScript interpreter fallback for compiled Blot programs.

## Run it

```sh
just demo
just build
just compile examples/prelude.blot build/prelude.wasm
just check
just bench
just ecs
just bench-ecs
just bench-native
just bench-incremental
just profile-ecs
deno task blot check examples/prelude.blot
```

The default build checks the pinned Bend version and runs `bend PROOF.bend`. It
compiles `compiler/native_main.bend` through Bend's native backend, which emits
C and invokes clang. Build tools require clang 14+, Deno, Bend 2.0.5, and Bun;
the pipe transport is POSIX. Generated compiler output is ignored.

Bend 2.0.5 has a reproduced native ownership bug: generic constructor payloads
can be reference-counted but later unboxed as unshared records. The build script
patches an isolated copy of its emitter to use `ctr_take` for every owned boxed
node; borrowed and packed paths are unchanged. It checks the exact patch site,
compiles and runs [a native regression](native_backend_regression.bend) at 1 and
4 threads, and only then publishes the compiler binary. Your installed Bend is
never modified. The JS reference uses the unmodified installed backend. Review
and retire this workaround when upgrading Bend, keeping the native regression
and cross-backend parity checks.

For repeated source-only iterations, run `just build` once, then
`just compile examples/prelude.blot build/prelude.wasm` or
`deno task blot check examples/prelude.blot`. These commands reuse the native
binary; rebuild it after changing the Bend compiler. Demo, benchmark, and test
tasks perform their own compiler build outside source compilation timings.
`build:compiler:js` explicitly builds the JavaScript reference backend through
Bend's installed loader; `build:compiler:all` builds both for parity tests. The
`bench` and `bench-ecs` benchmarks measure this JS reference. They include
source parsing, prelude linking and checking, const evaluation, and Wasm
emission. Bend bootstrap generation and Wasm instantiation are outside the timed
region. The fixtures cover ordinary higher-order code, a wide module of
independent functions, and a long forward dependency chain.

## Native subprocess API

```ts
import { createNativeCompiler } from "./compiler/native.ts";

const compiler = await createNativeCompiler({ threads: 1 });
try {
  const artifact = await compiler.compile(source);
  const ecs = await compiler.compileEcs(gameSource);
  const analysis = await compiler.analyze(source);
} finally {
  await compiler.dispose();
}
```

One executable stays alive across requests. Calls are asynchronous and queued;
each caller receives its own result. Disposal cancels pending work and reaps the
child. Compiler diagnostics retain source locations and do not terminate the
session; malformed transport/process failures are fatal. No native failure falls
back to executing the compiler in JavaScript.

[native_request.bend](native_request.bend) validates the incoming CST protocol;
[native_response.bend](native_response.bend) serializes complete public results.
[native_io.c](native_io.c) only reads/writes bounded length-prefixed u32 frames;
it implements no language semantics. Frames have a 64 MiB limit, strings use
Unicode scalars, and Nats retain all 48 bits. A versioned startup handshake
detects stale/incompatible binaries. Stdout is reserved for framed responses.

`just bench-native 7` compares the same 7/16/64-system workloads with JS and
native 1/2/4/8 CPU threads. It includes encoding, pipes, native compilation, and
response decoding in every native sample, reports startup separately, checks
exact public analysis/storage/Wasm parity, and executes the emitted ECS code.
Native requests currently rebuild the full source/prelude; retaining the process
is not yet declaration-level incremental compilation.

The [executable example](../examples/prelude.blot) exercises const and runtime
evaluation, closures, local/global polymorphism, nested `Maybe` patterns,
`Result`, early exits, and symbolic/backtick operators. The full syntax and ECS
design showcases still contain unimplemented features. The smaller
[ECS runtime example](../examples/ecs_runtime.blot) is executable.

## Executable language

```blot
fn identity value => value

export fn answer () => do:
  let same = fn value => value
  let enabled = same True
  let Some(value) = Maybe.map (fn x => x + 2) (Some 40) else:
    return 0
  if enabled:
    return same value
  return 0
```

- Generic nominal `data` declarations have nullary or unary constructors.
  Constructors are ordinary values, including unary constructor functions.
  Records, tuple payloads, and `type` aliases are not lowered yet.
- Named functions and lambdas use explicit currying and lexical capture.
  Qualified names such as `Maybe.map` are statically resolved names, not
  implicit receivers or type-directed dispatch.
- Annotations support Unit, U32, Bool, concrete applied data types, and pure
  function arrows. Data parameters scope constructor payload types; ordinary
  function generics are inferred.
- `case value:` arms use `pattern => expression`. Patterns include literals,
  wildcards, bindings, and nested constructors. `Some value` and `Some(value)`
  are equivalent. Matches must be exhaustive.
- `if let pattern = value:` binds in the successful branch only.
  `let pattern = value else:` requires an exiting failure suite. Their RHSs are
  pure and evaluated once. Plain pattern bindings must be irrefutable. This does
  not implement union/refinement types or typed union patterns.
- `do:` is an expression; `return` exits the nearest explicit block in the same
  function. Falling through yields Unit. Explicit labelled blocks/exits in the
  core prevent early returns from copying continuations.
- `let` requires a pure RHS. `use name <- expression` permits effects.
  `use expression` is exactly the discard binding. Pure use executes in consts
  and Wasm; it does not handle effects or construct a boxed action.
- U32 decimal/hex literals support separators and reject overflow. Arithmetic
  wraps at 32 bits. Bool and Unit have dedicated scalar representations.

[syntax.ts](syntax.ts) preserves original UTF-16 offsets through layout.
[lower.bend](lower.bend), [source_types.bend](source_types.bend), and
[operators.bend](operators.bend) lower source into [model.bend](model.bend).
Source entry points keep the lowered module inside Bend through analysis and
emission; only the final public result is decoded. The separate `CoreModule`
host API still validates and marshals externally supplied core values. Errors
report file/line/column. Baba syntax errors can still point to an enclosing
parser island rather than the precise unexpected token.

## Prelude and operators

[std/prelude.blot](../std/prelude.blot) is loaded once per source compiler and
linked as an ordinary source module. It defines `Maybe`, `Result`, `identity`,
`always`, `compose`, `flip`, `on`, mapping/binding/conversion functions, Bool
negation, and U32 operations.

Root declarations shadow implicitly imported prelude names. Prelude definitions
retain their own scope and nominal identities. Only root exports become host
exports. Use `createNativeCompiler({ prelude: "none" })` for a freestanding
module. General file imports/module graph loading are a separate next step.

```blot
infixl 60 (+) = add
infixl 70 (*) = multiply
infixl 10 `on`

fn add left => fn right => @u32.add left right
fn multiply left => fn right => @u32.mul left right
fn on combine => fn project => fn left => fn right =>
  combine (project left) (project right)

export fn answer () => 20 `add` 22
```

Fixity headers precede data/value declarations. Precedence is 0..255;
application binds tighter. Backtick functions default to left-associative 80.
Equal-precedence operators need compatible associativity; non-associative chains
require parentheses. Symbols have no compiler-hardcoded operation: headers
resolve to ordinary functions. The initial numeric prelude is explicitly
U32-specific. Static associated dispatch and demands are not faked; `&&` and
`||` are not supplied as incorrectly eager alternatives.

Numeric primitives are `@u32.add`, `.sub`, `.mul`, `.eq`, and `.lt`, each
requiring two operands. The explicit ECS bridge adds `@ecs.get Type`,
`@ecs.set value`, and `@ecs.insert value`. Arbitrary compiler functions/type
reflection remain outside the executable boundary.

## Inference and effects

[types.bend](types.bend) supplies occurs-checked unification. Substitution
resolution traverses type structure once and follows the ordered substitution
suffix only at variable leaves. Ground types do not repeatedly rebuild
themselves for unrelated substitutions. The order, occurs checks, and structural
traversal limits are preserved and differential-tested against the original
whole-type rewrite algorithm. [infer.bend](infer.bend) implements rank-1
Hindley–Milner inference: pure local bindings generalize and each use
instantiates its scheme. Top-level definitions are ordered by dependency
components in [dependency.bend](dependency.bend) and
[globals.bend](globals.bend); forward references and recursive groups work. The
dependency graph is decomposed once per module with two bounded DFS passes,
using persistent maps and sets rather than repeated reachability searches.
Recursion is monomorphic within a group; polymorphic recursion is not inferred.
Datatype arities/templates and pattern coverage are checked separately.

Function values are **pure arrows in this slice**. Creating an effectful lambda
or referring to an effectful named function as a value fails explicitly. Named
first-order calls retain transitive closed ECS effects, including cycles.
Effectful globals remain monomorphic so storage requirements can resolve from
callers. `use` bindings are also monomorphic. Effectful callbacks await arrow
effect rows; their effects are never silently erased.

[check.bend](check.bend) closes effects and validates purity after inference.
Both branches contribute effects, regardless of literal conditions. An effectful
`let` is rejected even if hidden behind a helper. Const initializers and
ordinary Wasm compilation may not execute ECS effects. Unresolved access types,
scalar accesses, invalid resource insertion, and missing descriptors fail.
`compileEcs` is the explicit provider-linked entry point described below.

The [core ECS fixture](fixtures.ts) still derives registrations, entity queries,
and ordered parallel scheduling batches. Read/read accesses do not conflict.
Resources do not filter entities; inserting a component does not require its
presence. Insertion is a structural barrier. Descriptors use (module identity,
declaration name), not compilation-order IDs. The executable ECS bridge uses
this same checked planning path.

## Executable ECS port

`just ecs` compiles and executes
[ecs_runtime.blot](../examples/ecs_runtime.blot). It adapts
`../gdev/src/ecs.blot` and its inferred-system test case into a smaller
bootstrap boundary: four component types, two resources, seven systems, and
ordinary getter/setter helpers with inferred effects.

```blot
#[component]
data Position = Position U32

fn read_position () => @ecs.get Position

export fn advance () => do:
  use position <- read_position ()
  let Position value = position
  use @ecs.set (Position (value + 1))
  return ()
```

- `#[component]` and `#[resource]` currently register known storage
  declarations. These two bootstrap tags are not general const-time declaration
  transforms. Storage declarations cannot have type parameters. `@ecs.get` takes
  a type name, not a constructor or an arbitrary runtime value.
- Read values have the same nominal ADT type as their constructors. Setter
  targets are inferred from values, including through named helpers; the
  scheduler does not search source spellings. Both branches contribute effects.
- `compileEcs` supports storage with exactly one constructor carrying `U32`.
  Richer layouts fail explicitly. All exported functions are selected system
  roots and must have type `Unit -> Unit`; private helpers may have other types.
- [ecs_abi.bend](ecs_abi.bend) derives storage bindings. [wasm.bend](wasm.bend)
  emits three imports in module `blot:ecs`: `read(tag)`, `write(tag, value)`,
  and `insert(tag, value)`, all using i32 words. Runtime tags are
  artifact-local; nominal `(module, declaration)` identities identify storage.
  Never persist tags as hot-reload IDs. The raw import ABI is non-reentrant.
- [ecs_runtime.ts](ecs_runtime.ts) instantiates Wasm and supplies an explicit
  world/entity invocation. It is host storage and iteration, not an interpreter
  for Blot functions. Component payloads use dense `Uint32Array` columns with
  presence bitsets; resources use separate scalar cells. `run(world)` returns
  the successor snapshot. Changed columns are copied once per transition;
  earlier snapshots and seeded inputs stay unchanged. Arrays stay private.
- `run` executes systems in declaration order, using inferred component-query
  intersections. Write-only access requires presence. Resource-only systems run
  once even with zero entities. Insert is an upsert and adds no presence filter;
  later systems see the inserted component. Insert-only systems with no entity
  query require `runEntity(world, entity)`, never an invented entity zero.
- The host checks access capabilities, refuses worlds from another runtime, and
  discards a transition if an import or Wasm call fails. Invocation state is
  cleared on failure. Inferred batches describe potential parallelism, but this
  host executes sequentially.

This is **not a verbatim port or a timing of the full gdev library**. It omits
spawn/remove, F32/F64 and record payloads, previous-frame reads, rendering
stages, general effect handlers, and reflective world generation. Compatible
state-preserving reload is described below. Storage iteration is in the host,
not generated Wasm; each storage operation crosses an import boundary.
Source-level first-class arrays and a zero-copy/native ECS storage backend
remain separate work.

### Measuring compilation

`just bench-native` compares native and JS compilation; `just bench-ecs`
measures only the JS reference, using the executable example and generated
16/64-system workloads, saving `build/ecs-bench.json`. Every timed sample starts
from source and includes Baba parsing, prelude linking/checking, Bend
type/effect inference, const evaluation, inferred queries/scheduling, and Wasm
emission. Frontend initialization and Wasm instantiation are reported
separately. Bend bootstrap generation, process/module loading, file reads and
ECS execution are excluded; this is full recompilation with a reusable frontend,
not an incremental or hot-reload measurement.

For JS reference measurements after `deno task build:compiler:js`, run:

```sh
deno run --allow-read=generated/wasm,examples,std --allow-write=build compiler/ecs_bench.ts 15 build/ecs-bench.json
```

The first argument selects samples per workload (default 7, with two warmups).
The optional second argument saves JSON;
`just bench-ecs 15 build/ecs-bench.json` accepts the same arguments and rebuilds
the compiler first. The report includes source lines, system/storage counts,
Wasm bytes, first-call, median, p95, and mean compilation times. `first_ms` is
the first call for each workload in the same process, not an independent
cold-process measurement. Each workload is validated, instantiated, and executed
outside the timed region. JSON also records individual sorted timings, the
runtime/platform, and the Wasm SHA-256 so changes can be checked for output
equivalence.

`just profile-ecs 64 5 build/ecs.cpuprofile` samples five full 64-system
compiles after warmup, prints self/inclusive CPU costs, and saves a standard V8
CPU profile. Open it in a CPU-profile viewer for call stacks. Deno's local
inspector API requires `--allow-sys`; the task grants it without opening a
remote debug port. For source-only profiling after building:

```sh
deno run --allow-read=generated/wasm,examples,std --allow-write=build --allow-sys compiler/ecs_profile.ts 64 5 build/ecs.cpuprofile
```

Use the unprofiled benchmark for comparisons: sampling adds overhead. Run
benchmarks serially, without compiler builds or test jobs competing for the CPU.

See [PERFORMANCE.md](PERFORMANCE.md) for the current isolated before/after
measurements, raw report paths, and remaining bottlenecks. Full rebuilds, fresh
incremental sessions, and edit-to-reloaded-world latency are separate
measurements; none includes rebuilding the Bend bootstrap itself.

Compiler metadata uses shared persistent indexes: source names/types, dependency
summaries, checker effect graphs, scheduling access masks, and backend
constructor/storage catalogs. [index.bend](index.bend) reads Bend's persistent
maps without reconstructing the map or search key. Ordered source lists still
determine diagnostics, emission order, and runtime tags. These are pure Bend
changes, not a JS inference shortcut or skipped validation.

## Evaluation and Wasm representation

[const_eval.bend](const_eval.bend) evaluates pure functions, closures, algebraic
values, matching, and block exits with lexical scope. One shared budget counts
evaluated core expressions across initializers; failed branches and skipped
tails do not run. Referenced const definitions are reevaluated, not cached.
Recursive evaluation exhausts a diagnostic budget rather than running unbounded.

[closures.bend](closures.bend) lifts lambdas and finds free captures.
[wasm.bend](wasm.bend) emits real Wasm binary code:

- Internal functions use `(environment: i32, argument: i32) -> i32`.
  U32/Bool/Unit remain unboxed words. Algebraic values contain a constructor tag
  and payload word; closures contain a table index followed by captured words.
- Immutable const closures/data are serialized into a static heap prefix.
  Internal polymorphic functions share a uniform word ABI after checking; this
  is not a dynamically typed language or a source-level `Any`.
- Host exports are scalar functions `(i32) -> i32` and immutable scalar globals.
  Data/closure exports are rejected pending a persistent host-value ABI. Unit is
  0, Bool is 0/1; JavaScript sees U32 as signed i32, so use `>>> 0` to inspect
  all 32 bits.
- Private linear memory uses a checked bump arena capped at 16 MiB. Export
  wrappers reset allocation to the static prefix on each call. Values cannot
  escape through the scalar host ABI. Overflow/growth failure traps. Memory
  retains its high-water allocation, but repeated calls do not accumulate arena
  use. Pure artifacts have no imports. ECS artifacts import only scalar storage
  operations; their provider prohibits reentrant execution and never exposes
  guest pointers or raw exports.

The arena is a bootstrap lifetime boundary, **not** the final representation for
persistent game state, arrays, hot reload, or unbounded allocation. Emitted
features are a conservative subset of Wasm 3.0, not a claim to use all its new
features. The
[binary format](https://webassembly.github.io/spec/core/binary/modules.html)
still uses binary version 1.

Selected independent checks/metadata operations use Bend's parallel-call syntax.
Native execution uses the requested CPU thread count; speedup must be measured,
not assumed. The JS reference runs those annotations sequentially.
Traversal/const/resource limits fail explicitly. Internal persistent lists/maps
are compiler representations, not Blot's future array representation.

## Incremental compilation and reload

This separate pipeline still uses the JavaScript backend. Build it once with
`deno task build:compiler:js`, then keep a compiler session open:

```ts
import { createIncrementalCompiler } from "./compiler/incremental.ts";

const compiler = await createIncrementalCompiler({ workers: 1 });
try {
  const first = await compiler.compileEcs(source);
  const next = await compiler.compileEcs(editedSource);
  console.log(next.stats);
  const reloaded = await runtime.reload(world, next.artifact);
  // Use reloaded.runtime and reloaded.world together. The old pair stays valid.
} finally {
  compiler.dispose();
}
```

`compile` provides the same incremental pipeline for pure scalar exports.
`compileEcs` links the explicit ECS provider ABI. `createSourceCompiler` remains
the clean-build oracle; the CLI still performs full builds. There is no file
watcher or persistent disk cache yet.

The caches distinguish the information that actually crosses a boundary:

| Boundary             | Reused when                                                                                           |
| -------------------- | ----------------------------------------------------------------------------------------------------- |
| Lowered declaration  | CST and declaration/fixity scope are unchanged                                                        |
| Dependency plan      | Named references, lambda identities, effect seeds, and nominal dependency edges are unchanged         |
| Checked group        | Owned declarations, required type/storage metadata, and imported type/effect interfaces are unchanged |
| Const evaluation     | Transitive referenced bodies/metadata and entering evaluation budget are unchanged                    |
| Function/lambda code | Its runtime IR and capture layout are unchanged                                                       |
| ECS query/schedule   | Exported system names and inferred effects are unchanged                                              |

Declaration-local source identities are separate from current UTF-16 diagnostic
offsets. Trivia does not change local names or closures. Closed, canonical
interfaces allow same-interface body edits to stop propagating through checking.
Inference variables are local to a group; public generic signatures are
equivalent modulo renaming of their quantified variables.

Pure dependencies can compile independently. Recursive groups and callers that
share a possibly effectful monomorphic helper remain coupled so their inference
constraints cannot diverge. This is conservative: even a fully concrete shared
effect helper can join callers into one job. Nominal dependency closures are
computed once per type SCC, then propagated through the inference-job DAG; each
job no longer walks the entire declaration/type graph independently. Native Bend
entry compilation uses balanced fork/join; the JS bootstrap uses persistent Deno
workers when requested. One lane runs inline, and two or more lanes use isolated
workers. No native parallel speedup is claimed by the JS benchmarks.

Code entries contain symbolic relocations for functions, constants,
constructors, and storage. Linking resolves indexes and LEB sizes after reuse;
changing a tag, constant address, or function order does not require compiling
all entries again. Symbol lookup reuses indexes built during preparation, as
does ECS storage metadata. Code/data sections carry measured byte chunks through
body/section sizing and flatten once into the final module. The compiler
serializes source revisions, waits for all jobs, and publishes caches only after
a successful complete build. Errors remain observable and disposal rejects
outstanding worker jobs.

`runtime.reload(world, artifact, { resources: [{ identity, value }] })`
validates and instantiates the new Wasm, remaps nominal storage identities, and
returns a new runtime/world pair. Existing immutable component columns are
shared safely; new components start absent. New resources need explicit seeds.
Removed storage or changed component/resource classification fails with
`incompatible_reload`. Constructor renaming and tag/index reordering are
supported because the current storage ABI is uniformly one U32 payload. This is
not arbitrary record-layout migration, guest-pointer persistence, or replacement
of an actively running call.

Measure all stages with `just bench-incremental 5`. It checks each artifact
against a clean build (bytes, types/effects, const values, plans) and executes a
reloaded world. It reports fresh 7/16/64-system builds,
identical/trivia/body/effect/layout/const/all-body edits, cache counts, and
1/2/4/8 lanes. Edit timing includes linking, Wasm compilation/instantiation, and
compatible state remapping. Compiler startup is reported separately; Bend
bootstrap, file reads, oracle checks, and state seeding are excluded. Samples
restore the baseline between edits, rather than measuring the same edited source
repeatedly. Fresh sessions retain first-use worker/JIT costs. A secondary
Wasm-only measurement may hit the engine cache and is not added to the
end-to-end total.

The cache stores only each current unit, not every historical revision.
Identical source bypasses parsing; other edits still parse the entire file.
Name/fixity changes can conservatively relower the file, and linking still
assembles the whole Wasm module. General module imports, incremental parsing,
persistent cache files, fine-grained layout migration, and moving these caches
and job boundaries into the native process remain separate work.

See [the measured results](PERFORMANCE.md) for the before/after full builds,
edit-to-ready latency, worker scaling, and reproducible report paths.

## Verification and remaining scope

`LAWS.bend`/`PROOF.bend` retain the ECS/query/purity/budget rules and add a
proof that an explicit return skips its continuation. These are selected
invariants, not a proof of whole-compiler correctness.

Tests compare const results with instantiated Wasm, check lexical scope,
polymorphism, exhaustiveness, fixity, nominal identity, diagnostics, effects,
unsigned bit patterns, UTF-8/multibyte encoding, and repeated calls. `just demo`
is the source-to-Wasm acceptance case.

Next boundaries: module imports, arrow effect rows/demands, const type values
and resolver execution, then the full source-library ECS case. Records,
arrays/SIMD, text/F64, closed unions, and general ownership/storage reuse still
require implementation. Resolver headers and `return $` parse but produce
explicit unsupported-lowering errors.

Design references:
[Hindley–Milner with effect rows (Koka)](https://arxiv.org/abs/1406.2061)
motivates preserving latent effects in function types rather than erasing them;
[SSA is Functional Programming](https://www.cs.princeton.edu/~appel/papers/ssafun.pdf)
supports a small functional control-flow core. Neither implies this bootstrap
already implements row polymorphism or SSA optimization.

# Native Carp semantic backend

This is an ahead-of-time **Carp port of the complete native source-compiler
request path**, not a JavaScript interpreter or a runtime call back to Bend. The
existing Baba/TypeScript source frontend is shared. Type inference, effects,
constant evaluation, lowering, Wasm emission, request decoding and native cache
state execute in the Carp-generated native binary.

`generated/` contains 6,531 Carp functions, including lifted closures, split
across 57 semantic compilation units plus a driver. It is a mechanical semantic
port rather than a hand-written redesign. The small C runtime supplies value
representation, reference counting, floating-point/string primitives, POSIX
transport and a worker pool. There are no Blot language rules in that runtime.

## Build and run

Requirements: pinned Carp 0.6.0, Python 3.10+, and a C11 compiler on a 64-bit
POSIX host. Tested here on Linux x86-64 with Clang. Set `CARP_DIR` to the pinned
Carp checkout, and put `carp` and `clang` on PATH (or set `CARP` and `CC`).
Normal builds need **neither Bend nor Node**.

```sh
python3 compiler/carp/port/build.py release
# Alternatives: debug, sanitize. Builds accept --jobs 1..32.

deno task blot:carp check examples/records.blot
deno task blot:carp build examples/arrays.blot build/arrays.wasm
```

Source commands use Deno and the shared frontend; the native executable itself
speaks the existing binary protocol on stdin/stdout. It is not a second text
parser. Failed CLI compilations preserve any existing output file.

```ts
import {
  createCarpCompiler,
  createCarpIncrementalCompiler,
  createCarpProjectCompiler,
} from "./compiler/carp.ts";

const compiler = await createCarpCompiler({ threads: 4 });
try {
  const artifact = await compiler.compile("entry const answer = 40 + 2");
  // artifact.bytes is Wasm with the unchanged blot:abi version 2 manifest.
} finally {
  await compiler.dispose();
}
```

The three constructors have the same options and return interfaces as their
existing `createNative*` counterparts. The old APIs remain available. Their
shared types/options now live in `host_model.ts`, so loading the Carp APIs does
not inadvertently load the Bend JavaScript oracle.

The earlier hand-written scalar experiment remains at `compiler/carp/*.carp` and
builds to `generated/carp/blotc-carp`. Its restrictions do **not** describe this
full semantic backend. No existing default command is silently redirected.

## Compatibility surface

The port includes the original native implementations of:

- Rank-1 and local polymorphism, constraints/evidence, recursive components,
  first-class functions, captured closures and higher-order calls.
- ADTs, tuples, named records, exhaustive/nested/multi-value/value patterns,
  immutable arrays and alias-safe updates/iteration.
- Effects/providers, typed state, descriptors, callback effects, source prelude,
  import resolution input, custom operators, methods and expression tags.
- Const evaluation and budgets, entry reachability, numeric-array and callback
  guest ABIs, long-lived guest execution and native incremental/project
  sessions.
- Transactional cache invalidation, failure recovery, diagnostic encoding and
  deterministic source-order results with one or multiple native workers.

Tests establish compatibility for their exercised inputs, not a proof that an
arbitrary program or a different host platform is equivalent. The original
compiler remains the independent oracle, and its internal model-only JS API
remains unchanged rather than being relabeled as a Carp API.

## Memory and execution

Heap values are reference counted; there is no tracing collector. Each native
function owns its temporary frame. Mutually exclusive lexical scopes reuse
slots; tail transfers reuse that dispatcher's allocated frame storage. Borrowed
local field/tag reads retain only escaping values, not the enclosing record.
Scalar retains/releases inline to no-ops. Per-worker allocation/release counts
are aggregated after joining; shared object reference counts remain atomic.
Releases use an iterative worklist. Unicode strings use shared, flattened UTF-16
views. Reserved NaN payloads are boxed so numeric bits cannot be mistaken for
pointers. NaN payloads and signed zero have regression tests. Name equality uses
the flat UTF-16 representation instead of allocating per-character views; 15,225
independent comparisons check the rewrite against the pinned semantic
definition, including NUL and surrogates.

The weighted `inference_batch.execute` boundaries submit real native work to a
cooperative pthread pool. Awaiting threads help queued tasks, avoiding nested
fork/join deadlock; results are joined in source order. Worker counts are 1..64.
`--runtime-stats` prints task/allocation totals to stderr at shutdown; stdout
remains exclusively the protocol. This does not imply every compiler stage
scales with worker count.

Static and captured-function tail calls transfer owned arguments to a native
dispatch loop instead of retaining the caller's stack frame. Terminal
call-then-bind patterns use an explicit heap continuation stack; the
continuation itself remains compiled Carp code. This supports the regression
with 20,000 recursive const-evaluation calls without growing the native stack at
each bind. It does not change source evaluation order or the const-step budget.

The protocol retains its 16,777,216-word frame ceiling and 48-bit Nat bounds.
The generic native call guard is 16,384 active non-tail calls; this is a host
resource guard, not a bound on source recursion in emitted Wasm. Direct
self-tail-recursive input functions are lowered to loops; the list operations in
`loops.cjs` are also made iterative, including large response lists. Native
stack/resource limits can still differ from the reference implementation.
Pointer payloads require host addresses fitting in 48 bits; Windows/32-bit hosts
are not claimed.

## Regeneration and provenance

The semantic input was emitted by Bend 2.0.32 from
`compiler/carp/port_reference.bend` at commit
`700c698bdb65db048e38dc87f059559be18023e2`. `reference.lock.json` records the
exact input hash and tool versions. This commit merges `main` at
`ac59fb68f98780e168ce01fa39410b1a6ef54efd`. The producing Actions checkout was
`0be4d2e35679e6c4c00f4a20940f2c2c9c72d294`; both commits have the verified tree
`e43b01f6c75740326c002063b3a7eea7ceda352b`. Earlier local reports named a PR
head instead of its Actions merge snapshot; the lock now distinguishes them. The
generation-only Acorn 8.15.0 parser is vendored; no npm download is needed. See
`NOTICE` and `licenses/` for source attribution.

```sh
bend compiler/carp/port_reference.bend -o generated/carp-port/reference.mjs
python3 compiler/carp/port/check_generation.py generated/carp-port/reference.mjs
python3 compiler/carp/port/generator_test.py generated/carp-port/reference.mjs
node compiler/carp/port/optimization_test.cjs generated/carp-port/reference.mjs
python3 compiler/carp/port/layout_test.py --sanitize
python3 compiler/carp/port/build_test.py

# Deliberate regeneration after updating the reviewed semantic lock:
node compiler/carp/port/generate.cjs generated/carp-port/reference.mjs compiler/carp/port/generated
python3 compiler/carp/port/verify.py
```

The generator rejects unrecognized syntax and mismatched input hashes. The
manifest seals emitted source bytes and the generator/list-rewrite/parser
versions. A source rewrite validates Unicode before constructing a character,
retaining the native decoder's recoverable diagnostic behavior rather than
reproducing an eager-construction failure in Bend's JavaScript output. Builds
verify that manifest before invoking Carp. Altering language semantics requires
updating the port and its reviewed provenance, not relying on a hidden fallback
to the old compiler. This snapshot is not a proof of correctness of the
translation.

Carp emits C into independent translation-unit directories. The C is compiled
unchanged; it is never patched. Content-addressed Carp-to-C output is shared
across debug/release/sanitizer builds. Separate object, link and runtime-test
receipts keep unchanged work out of rebuilds; `--rebuild` bypasses them. Every
output's hash is rechecked, tool executable bytes participate in keys, and
source snapshots prevent racing edits from being published as current. The
public executable is not touched by a no-source-change build. `build_test.py`
exercises invalidation, corrupt-cache repair and failed compiler/test
publication using observable fake toolchains. A failed build does not replace
the last working executable. Debug, release and sanitizer binaries are retained
under `generated/carp-port/<mode>/`.

## Verification

```sh
python3 compiler/carp/port/verify.py
deno task test:compiler:carp
deno task test:compiler:carp:workers
python3 compiler/carp/port/standalone.py

# Require the independent generated JavaScript oracle and its dependencies:
python3 compiler/carp/port/run_suite.py --native-only
python3 compiler/carp/port/run_suite.py --source-only
```

Each new binary is checked with `runtime_test.c` against that mode's objects. An
unchanged rebuild reuses the verified test-success receipt; `--retest` runs
those checks again without rebuilding. CI always passes `--retest`. The
clean-EOF tests require normal process exit (not API cancellation via SIGTERM),
so ownership accounting also checks request, worker and cache cleanup. The
standalone test copies only host/frontend code, parser Wasm, source examples and
the Carp executable into a clean tree. The worker probe checks real compiler
batches, worker execution counts and identical serial/parallel Wasm. It has no
`generated/compiler` directory, Bend binary or generated Bend JavaScript. It
also checks CLI output and failure-safe publication.

The native suite preserves the original JS compiler as an independent oracle.
The source suite runs the unmodified test files but redirects the synchronous
`createSourceCompiler` test API to native Carp. `CARP_SOURCE_EXECUTIONS` records
real process invocations. Model-only JS tests in that suite remain reference
regressions and must not be counted as additional Carp implementations. The
adapter is test-only, never a production fallback.

The test runner temporarily selects Carp at the existing native test path,
serializes that selection with a lock, and restores the old executable even when
tests fail. An interrupt propagates normally after restoration.

## Measurements

Compiler builds and source compilation are separate measurements:

```sh
python3 compiler/carp/port/build.py release
# Per-unit Carp/C timings and cache hits: generated/carp-port/release/build.json
deno task bench:carp 7
```

The benchmark retains one process and frontend per configuration, warms each
source three times, rotates backend order between rounds, then times
source-to-Wasm requests with `analysis: false`. It checks the guest result and
output equality outside the timed region. Its JSON records all samples and
complete workloads. It compares one and four Carp workers; optional pairs of
reference executables and explicit optimization labels can be passed to
`compiler/carp/bench.ts`. Different optimization settings are not a fair
language-speed comparison. Neither small-workload timings nor build-cache hits
establish a whole-language performance ranking.

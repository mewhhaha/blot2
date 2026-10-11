# Resolved source bodies

`core_backend.Emitter.prepareBody` owns a specialization-local sidecar for one
source root. The sidecar copies its exact type and row substitutions and owns
variable-length call arrows, projection cases, capture layouts and roles,
static-pattern bindings, and request operation labels. Core operands and lists
remain immutable borrows. Evaluator, layout and substitution handles stay inside
the owning Generator; no body survives into a retained project or artifact.

Node lookup stores a tag and offset into one aligned payload buffer. Only the
selected variant occupies payload space. Lookup copies borrow nested storage;
payload pointers survive until the next insertion. Preparation reacquires a
pointer after recursive work, and encoding borrows only from the sealed body.
Ownership transfers after both table and payload allocation succeed.

Every named function, closure, runtime initializer and inline source-body route
prepares this owner before encoding that body's source operations. A separate
preparation Emitter carries symbolic bindings and source scope stacks. It cannot
emit instructions or allocate runtime locals. Nested computation factories are
described from source plans without reserving functions. A missing plan slot is
an implementation error, with no semantic-selection fallback.

Preparation selects named and associated callees, resolver strategies,
application arrows, field cases, type identity, capture substitutions and roles,
static patterns, demand forwarding shapes and semantic operation labels. Returns
and breaks name source scopes. Encoding binds those selected scopes to current
machine labels and cleanup marks; those runtime handles never enter the semantic
plan.

Encoding still owns layout-to-machine loads and stores, environments, local and
label allocation, cleanup execution, static value evaluation/serialization and
lazy function or wrapper reservation. Runtime operation tokens are interned from
prepared semantic labels at the original encoding points. Synthetic helper
functions and closure capture-load prologues remain direct machine encoding.
Inline specialization may refine exact child substitutions from static values;
that child always owns a newly prepared body before its source is encoded.

Existing `prepared_*` counters retain their executed-shape meanings. The new
`resolved_bodies`, `resolved_plan_entries` and `resolved_plan_reads` distinguish
owned preparation from its consumption. Source-only factory metadata probes do
not count as emitted source bodies.

The owner and frozen-Core allocation-failure laws are registered in the native
suite. Executed guest laws cover calls, staged accessors, callback rows,
captured closures, demand forwarding, structured flow and request factories.
Qualification must compare diagnostics, constant steps, code instances, shape
counts and Wasm against the preceding compiler. Debug development timings cannot
establish a release performance improvement; preparing copied maps and factory
descriptions adds work whose CPU and allocation cost needs release
qualification.

## Qualification (11 October 2026)

Implementation `b068dc9` jointly qualifies 028, 036, 094 and 098. Zig 0.17.0 and
Deno 2.9.7 pass `deno task test:compiler`: the complete native gate and 763
guest/client laws. The pinned zig-analyzer checks 323 files with zero findings.
Every-allocation-failure/frozen-Core laws pass, including source-less constraint
origins, and all eight compile-allocation budgets remain unchanged.

[Artifact and input pins](qualification/resolved-bodies-pins.json) identify the
preceding qualified `0c5be56` compiler (`3829910f…47b`) and candidate
(`8a7dd393…a8bc`), harnesses, library/public input hashes and captured private
corpus hashes. Private source and raw logs remain in ignored
`build/bench/resolved-bodies/`; only hashes and aggregate results are recorded.

Seven alternating release pairs cover all 13 public examples, four synthetic
workloads through fresh/restart/population/first-edit/subsequent-edit/no-op, and
native typed assets through
fresh/no-op/edit/revert/rejection/recovery/fresh-edit. Successful Wasm, constant
steps, code instances and existing prepared-shape counters match. Native assets
preserve exact snapshots and dependency identities, 34 unchanged asset reuses
and last-good revisions after rejection. Nine failed CLI cases preserve status,
codes, source spans, messages and explanations; the comparison normalizes only
optional `related`/`details` absent versus null. Independent project-wire laws
also pass, including absent `related` on ordinary diagnostics and defensive
decoding of secondary locations.

The captured current gdev corpus uses both `src` and `devtools` asset roots: 55
modules, 482 fixture cases and 1,460 assertions pass. Its blocked split-hauling
module passes all 12 exports and 25 assertions. Earlier one-root fixture
failures omitted required inputs; the corrected capture records both roots. This
corpus is distinct from task 002's missing historical manifest.

[Public medians](qualification/resolved-bodies-public.csv) record CPU, wall
time, requested allocation, peak allocation and zero live allocation. Requested
bytes fall in 11 of 13 examples; arrays increase 0.24% and monads increase 3.1%.
CPU ratios range from 0.939 to 1.023. These mixed measurements overlap unrelated
host work and establish no overall speedup.

[Native-asset medians](qualification/resolved-bodies-native.csv) retain all
seven phases: fresh CPU 1,420 → 1,350 ms, edit 620 → 630 ms, revert 580 → 550 ms
and fresh edited process 1,340 → 1,410 ms. No-op/recovery CPU is quantized at 10
ms. Synthetic fresh CPU is 19 → 17 ms (monomorphic chain), 15 → 17 ms (generic
chain), 8 → 8 ms (diamond) and 28 → 26 ms (fanout); retained samples share that
10 ms quantization. Pins record raw load conditions and phase medians.

Compact tagged payload storage avoids allocating the largest plan variant for
every hash bucket. Per-variant ownership transfers only after capacity succeeds;
preparation reacquires payload pointers after recursion. The pre-compaction
integration failed three unchanged allocation budgets and is preserved as failed
evidence, rather than presented as a qualified compiler.

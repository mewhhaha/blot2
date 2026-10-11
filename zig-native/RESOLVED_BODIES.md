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

# Language evolution

The user approved all ten directions on 2026-10-06, plus typed external asset
imports. This is one migration program, not a claim that the features below are
implemented. `compiler/guide.md` remains the executable language reference.

All mechanisms must work for ordinary user modules. The compiler must not
recognize prelude, JSON, shader, ECS, or framework declaration names. Keep the
500 ms cold / under 100 ms retained-edit targets; measure extra inference work.

## Dependency order and acceptance gates

Implemented foundations so far: typed asset imports through the host API with
JSON and shader-adapter execution laws; inferred `@hole` diagnostics with owned,
bounded type graphs, lexical scope, and generic requirements; transparent
generic/imported type aliases retained in dependency interfaces. Named contracts
compose parameterized predicate bundles, including imported and qualified
contracts, with separately instantiated evidence and latent rows. Record
literals, exact record aliases, field-preserving type-changing updates, and
generic `@record.merge` now share stable layouts. `std/path` provides pure
getter/setter paths, whole-value identity, composition, type-changing writes and
effectful modification. Their contracts survive imports and serialized
dependencies. Completion gates below remain open unless explicitly documented as
current behavior in the language guide.

| Direction                   | First executable boundary                                                                            | Completion gate                                                                         |
| --------------------------- | ---------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| 1. Explainable inference    | Implemented: typed holes, structured types, lexical scope and generic requirements                   | Dispatch explanations and editor completion                                             |
| 2. Module abstraction       | Explicit exports and transparent aliases                                                             | Opaque representations, import/re-export privacy, interface cutoff, zero-cost wrappers  |
| 3. Generic contracts        | Implemented: named, parameterized bundles of existing predicates with imports and dependency bundles | Associated type members, implementation declarations, richer evidence diagnostics       |
| 4. Generic scoped effects   | Symbolic operation arguments in written rows                                                         | Distinct same-typed instances, handler subtraction, escaping-capability rejection       |
| 5. Usage/lifetime contracts | Inferred usage/capture facts with checked boundaries                                                 | Unique/shared, borrowed, once/many, resource cleanup, sound separate compilation        |
| 6. Extensible records       | Implemented: structural rows, stable layouts, type-changing updates and `std/path` composition       | Passed: aliases, captured callbacks, effect ordering, dependencies and checkpoints      |
| 7. Polymorphic packages     | Annotated higher-rank inputs and existential packages                                                | Skolem-escape rejection, evidence passing, specialization, heterogeneous packages       |
| 8. Typed staging            | Typed asset module construction at a host boundary                                                   | Typed Blot code values, descriptors, hygienic generation, exact staged dependencies     |
| 9. Erased proofs            | Explicit witnesses for bounded numeric/index facts                                                   | Branch facts, bounds-check elimination, erased evidence, bounded checking costs         |
| 10. Structured concurrency  | Capability/capture contracts from 4 and 5                                                            | Scoped tasks, defined cancellation, disjoint-access proofs, host execution              |
| 11. External assets         | Implemented: explicit host parser references returning typed modules and host references             | Passed: JSON/shader adapter laws, snapshots, tracked reads, retained edits and recovery |

Implement 1–4 alongside the typed asset boundary, then usage contracts and
structural records. Higher-rank packages and typed staging build on those type
identities. Refinements must start with a bounded solver. Concurrency depends on
proven capability identities and ownership, not merely effect labels.

## External asset boundary

An asset parser is an explicitly configured function. It consumes immutable
bytes through tracked reads and returns type descriptions, typed values, and
optional symbolic references to host resources. Generated declarations pass
through the ordinary compiler. Unsupported descriptions fail explicitly.

Host references publish the exact bytes parsed, a content digest, origin, and
media type alongside Wasm. Guest code carries only a scalar handle in an
ordinary nominal wrapper. A host must use the manifest from that build; opening
the origin again could silently load different bytes.

Changes to any tracked input rerun its parser. Identical generated source reuses
ordinary native frontend results. Failed parsing or compilation must not publish
candidate assets or replace the last successful compiler revision. Source
overlays, parser dependencies, deterministic reference assignment, and source
limits are part of correctness. Parser callbacks must be deterministic and
perform file reads through their supplied context.

The initial host parser boundary does not pretend that Blot already has runtime
text or general type-valued computation. Those remain separately specified
language work. No regex-based WGSL parser should claim to validate shader types;
shader integration should use a real parser or explicit checked metadata.

## Implemented representation safeguards

Generic substitution now preserves shared type nodes. A type DAG representing
2^64 leaves can instantiate as 64 product nodes instead of expanding into an
exponential tree. The memo belongs to one exact substitution; chronological
variable views and fresh row identities remain separate. This applies to every
generic instantiation, with no source-module or declaration-name recognition.

Hole diagnostics have bounded depth, node visits, text length and lexical scope.
Aliases publish their quantified row parameters explicitly so open latent rows
remain importable. Named contracts publish only parameter patterns and ordinary
predicate templates; their source AST and inference scratch do not escape into
dependency files.

## Verification

The current native suite, 589 guest/client tests and zero-finding analyzer gate
pass. Typed-path laws cover type-changing composition, identity, aliases,
captured callbacks, twelve-level composition, large accessors, early returns,
effect sequencing, incompatible source types, effectful accessor rejection,
dependency bundles, checkpoints and failed-edit recovery. Native
allocation-failure sweeps also check frozen-Core immutability. A separate
725-invocation comparison preserves existing diagnostics, constant steps,
code-instance counts and Wasm bytes.

Seven alternating gdev pairs preserve Wasm and deterministic work counters.
Fresh CPU is 636 / 637 ms before/after the path change; population and first
edit are unchanged, while subsequent edits measure 130 / 140 ms. The cold and
retained-edit targets remain open. See [STATUS.md](STATUS.md) for current
measurements and remaining compiler work.

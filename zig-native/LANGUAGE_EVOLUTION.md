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
generic `@record.merge` now share stable layouts. Their contracts survive
imports and serialized dependencies. Completion gates below remain open unless
explicitly documented as current behavior in the language guide.

| Direction                   | First executable boundary                                                                            | Completion gate                                                                         |
| --------------------------- | ---------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| 1. Explainable inference    | Implemented: typed holes, structured types, lexical scope and generic requirements                   | Dispatch explanations and editor completion                                             |
| 2. Module abstraction       | Explicit exports and transparent aliases                                                             | Opaque representations, import/re-export privacy, interface cutoff, zero-cost wrappers  |
| 3. Generic contracts        | Implemented: named, parameterized bundles of existing predicates with imports and dependency bundles | Associated type members, implementation declarations, richer evidence diagnostics       |
| 4. Generic scoped effects   | Symbolic operation arguments in written rows                                                         | Distinct same-typed instances, handler subtraction, escaping-capability rejection       |
| 5. Usage/lifetime contracts | Inferred usage/capture facts with checked boundaries                                                 | Unique/shared, borrowed, once/many, resource cleanup, sound separate compilation        |
| 6. Extensible records       | Structural rows and field-preserving updates                                                         | Composable typed paths, stable layout, sharing and evaluation-order laws                |
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

## Verification checkpoint — 2026-10-06

`deno task test:compiler` passes: the native suite and 501 guest/client tests.
The editor grammar/highlight checks and formatter checks pass. The analyzer
reports no errors and 122 warnings: 121 pre-existing findings and one ownership
warning for nested binding names in `Snapshot.clone`. Those names are released
by `Snapshot.deinit`; exhaustive allocation-failure checks cover cloning and
cleanup. The startup-stall fixture uses the normal two-second allowance so its
PID is recorded before intentionally withholding the protocol greeting.

The final seven alternating paired `gdev` runs pin all 43 source files and both
executables. Fresh native CLI median: 791.0 ms in the comparison snapshot, 793.8
ms with these changes; CPU: 743.8 / 744.4 ms; peak RSS: 63,768 / 63,764 KiB.
First retained comment edit: 231.2 / 237.0 ms; revert: 191.9 / 201.6 ms; no-op:
2.1 / 2.1 ms. These are warm-filesystem measurements, with fresh processes
separate from populated sessions. The 500 ms cold / under-100 ms edit gates
remain open.

The comparison executable already contains the early asset/alias/hole work; it
is not the original repository HEAD. Canonical field layout changes final Wasm
bytes, so each variant checks its own exact fresh/edit/revert/no-op parity;
execution laws establish behavior. Raw samples, compiler hashes and source
hashes are in the local ignored
`build/language-foundations/gdev-records-timings.json`. An earlier run under
changing machine load is retained separately as
`gdev-records-timings-loaded.json`; its wall-time medians are not a speed claim.

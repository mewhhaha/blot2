# Language evolution

The user approved all ten directions on 2026-10-06, plus typed external asset
imports. This is one migration program. The implementations below have distinct
qualification boundaries; [the guide](../compiler/guide.md) remains the
executable language reference.

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
dependencies. The table separates implemented behavior from remaining combined
qualification; focused implementation does not complete a release gate.

| Direction              | Implemented boundary                                                                           | Remaining qualification                                                        |
| ---------------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Explainable inference  | Typed holes, bounded diagnostics, dispatch explanations, completion and LSP                    | Covered by prior compiler gates and current editor/client laws                 |
| Module abstraction     | Public/private declarations, forwarding, opaque identities and wrapper erasure                 | General interface-cutoff and final performance qualification                   |
| Generic contracts      | Named bundles, associated members, implementation declarations and evidence diagnostics        | Prior qualified language behavior; final combined regression gate              |
| Scoped effects         | Fresh identities, symbolic rows, exact handler subtraction and bounded lifetime/capture proofs | Final combined portable composition; documented unknown-flow rejection remains |
| Usage and lifetimes    | Unique/shared, loans, once/many, cleanup transfer and cancellation                             | Final combined ownership/portable proofs and tracing replacement               |
| Extensible records     | Stable structural layouts, aliases, type-changing writes and std/path                          | Qualified; current combined regression gate                                    |
| Polymorphic packages   | Annotated higher-rank carriers, skolems, existential openings and dictionary ownership         | General portable composition and final combined qualification                  |
| Typed staging          | Typed code/descriptors, quote/lift/splice/emit, hygienic owners and exact input reuse          | Final combined staged capture, dependency and performance qualification        |
| Erased proofs          | Numeric/index witnesses, branch facts and bounded check elimination                            | Qualified in the 15 October full freeze; later combined regressions pending    |
| Structured concurrency | Cooperative scopes, spawn/join, cancellation, disjoint partitions and host Task ABI            | Final tracing replacement, portable composition and combined gate              |
| External assets        | Typed host/native imports, tracked JSON/shader inputs, manifests and recovery                  | Qualified; current combined regression gate                                    |

These dependencies govern the implementations: scoped identities precede usage
and captures, packages/staging retain those identities, and tasks depend on
checked lifetimes and ownership. Bounded conservative rejection remains part of
the language contracts. None of these mechanisms recognizes a privileged source
module or declaration spelling.

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

## Historical typed-path qualification

The typed-path milestone passed its native suite, 589 guest/client tests and
zero-finding analyzer gate. Typed-path laws cover type-changing composition,
identity, aliases, captured callbacks, twelve-level composition, large
accessors, early returns, effect sequencing, incompatible source types,
effectful accessor rejection, dependency bundles, checkpoints and failed-edit
recovery. Native allocation-failure sweeps also check frozen-Core immutability.
A separate 725-invocation comparison preserves existing diagnostics, constant
steps, code-instance counts and Wasm bytes.

Seven alternating gdev pairs preserve Wasm and deterministic work counters.
Fresh CPU is 636 / 637 ms before/after the path change; population and first
edit are unchanged, while subsequent edits measure 130 / 140 ms. The cold and
retained-edit targets remain open. See [STATUS.md](STATUS.md) for current
measurements and remaining compiler work.

## Settled language contracts (13 October 2026)

The reviewed design documents are complete:
[usage/lifetimes](USAGE_CONTRACTS.md),
[annotated polymorphism/packages](POLYMORPHIC_PACKAGES.md),
[typed staging](TYPED_STAGING.md) and
[structured tasks](STRUCTURED_CONCURRENCY.md). They share explicit
type/row/region binders and portable ownership/evidence. Their implementations
now have focused Source, immutable-Core and executed Wasm evidence. Final
combined gates remain as listed above. Examples in design documents are
contractual proposals unless the guide documents their exact executable syntax.
[Design qualification](LANGUAGE_DESIGN_QUALIFICATION.md) records checks.

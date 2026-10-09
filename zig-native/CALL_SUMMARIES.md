# General call summaries

This is the implementation specification for extending the current first-order
summary queue. Predicate-bearing functions, general higher-order calls, lexical
closures, recursive components and canonical specialization keys remain
implementation work. This document does not change language syntax or admit
programs rejected by the language's existing inference rules.

The existing boundary is in `core_eval.zig`: `CallSummaries`,
`ClosureRegion.collectCall`, `summaryInputs`, `solveSummary`, `beginSummary`,
`expandSummary` and `Session.principalEvidence`. Frontend schemes already retain
shared callee uses. Declared global functions with predicate-free schemes can
already share those schemes, including quantified callbacks and effect rows. The
separate job queue currently accepts closed first-order inputs. These paths
remain the baseline and the fallback during migration.

## Two different results

A **principal summary** describes a checked body in terms of its own quantified
inputs, residual requirements and lexical inputs. It does not choose a caller's
implementation, provider or result type. A **call judgment** proves one
instantiation of that summary against complete semantic evidence. Never store a
call judgment in the principal-summary cache.

Both results contain a schema version, checking mode, body identity, interface
graph, dependency certificate and diagnostic origins. Principal results also
contain binders and residual obligations; completed judgments instead contain
their solved evidence and selected source implementations. An unresolved
obligation is legal in a principal result only when explicitly exported as a
residual requirement. It is never legal in a completed call judgment.

The three modes are `source_interface`, `principal` and `selected`. The first
checks source admission without demanding values; the second has no expected
type or caller-selected seeds; the third may consume validated evidence supplied
by its caller. Modes are part of every key. Existing source-interface checks and
complete demand-body checks must not acquire selected-mode shortcuts.

## Owned graph representation

Use dense immutable node and edge arrays owned by the summary store. A node ID
is meaningful only with its graph owner. Binder IDs denote summary-local type,
row or evidence variables; they never denote variables in a live solver.
Importing a summary allocates fresh region variables for its binders and retains
sharing within that import. Two imports cannot accidentally unify their fresh
variables. A substitution maps each binder exactly once and preserves
chronological substitution windows in the receiving solver.

The graph has the following logical records; field names here define the API
contract, not a required Zig memory layout.

| Record         | Required contents                                                                                                                                               |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BodyIdentity` | Source unit identity, binding or anonymous closure identity, exact body fingerprint, checked interface/catalog identity and summary schema version              |
| `Binder`       | Kind, owning binder scope, ordinal, and any source-declared bounds; never a raw `types.Id` from another owner                                                   |
| `Interface`    | Ordered parameters, result, latent effect row, and declared row-closing decisions                                                                               |
| `Predicate`    | Current checker obligation kind, ordered operands, result/expected operands, evidence output slot, deferred-member state and source origin                      |
| `CalleeUse`    | Referenced summary identity, binder substitution, argument/result/effect relationships and origin; a shared edge rather than a copied transitive predicate list |
| `CallbackUse`  | Formal callback slot or captured callback slot, invocation type arguments, argument/result relationship, latent effect-row relationship and origin              |
| `Capture`      | Ordered lexical binding identity and version, type/row interface, evidence requirements, alias class and value-dependency classification                        |
| `Dependency`   | Exact body/interface/catalog/identity read, selected-evidence read or captured semantic observation, with its validity domain                                   |
| `Origin`       | Owning source identity, bounded source span, local obligation ordinal and argument/result witness role                                                          |
| `Component`    | Ordered member identities and the edges requiring joint inference; stable within the admitted dependency graph                                                  |

`Predicate` covers all current obligation kinds, including dispatch, result
dispatch, field/writable-field, collection, record merge/update, operations,
handlers, type/effect representation and type comparison. An unknown kind
declines admission. Exported predicates retain the checker's candidate order,
receiver rules, deferred status and row-closing rules. No summary-specific
dispatch precedence is introduced.

Use graph references for shared callee requirements and repeated type/effect
subgraphs. Do not flatten a diamond into its transitive paths. Every graph edge
has an owner and a checked index. Graph import rejects cycles that are not
represented by a component, out-of-range indices, inconsistent binder kinds and
unsupported versions.

## Admission and caller interface

The conceptual store operations are:

```text
describe(body, mode, lexical_interfaces) -> ready_principal | deferred | declined
request(summary, complete_inputs, mode) -> complete_judgment | ticket | open | declined
import(summary_or_judgment, region, fresh_binders, witness_map) -> obligations
advance(ticket, work_budget) -> waiting | complete_judgment | declined
```

`describe` checks what the body itself proves and exports the remaining
requirements. It performs no constant evaluation solely to make a summary
eligible. Source declarations, catalog entries and lexical interfaces must be
known. For unsupported source forms or incomplete lexical evidence it declines
without caching a false global ineligibility result.

`request` may enqueue an independent solver job only when every semantic input
that the job consumes is represented in the key. Open caller variables cannot
cross that boundary. A caller with open types imports a fresh copy of the
principal binders and residual obligations into its own region instead. It may
request a closed judgment after those inputs become complete. This preserves
bidirectional and result-directed checking without pretending that an unknown
result is a closed input.

For result-directed predicates, either the expected result is a complete keyed
input or the principal summary exports the relationship for caller-side
checking. Never close an open result just to schedule a job. The same rule
applies to callback results, open effect tails and selected evidence.

Arguments carry a separate witness map from original source expressions to
summary parameter/evidence slots. It is attached to the use, not interned as
part of semantic equality. Two equivalent uses may share a judgment while
reporting failures at different argument spans.

## Higher-order obligations and effects

Represent a formal callback parametrically. For example, a combinator that
invokes `step accumulator element` records relationships among the two argument
types, the returned accumulator and the callback's latent effect row. It does
not describe the callback as a fresh unconstrained arrow and discard its
requirements. Repeated invocations share the formal slot but retain their
distinct source origins and any distinct instantiations.

An unknown runtime callback remains valid when its checked function interface
proves the required calls. Its executable identity need not be known for a type
judgment. A known callback with residual requirements supplies its principal
summary and capture interface. If selection, stage evaluation or a special
representation depends on callback identity or values, those observations must
be explicit inputs to that selected judgment; otherwise leave it open.

Higher-order results may themselves export callback slots and relationships.
Quantified callback instantiations freshen their own binders at the same points
as ordinary checking. The summary mechanism adds no higher-rank inference and
does not change value restriction or generalization.

Effect rows retain operation identities, effect arguments, multiplicity where
represented, open tails and principal closing decisions. Callback effects join
the enclosing latent row exactly where ordinary checking does. Handler
subtraction preserves the existing instance/provider identity rules. A pure use
cannot make an effectful callback principal, and a handled use cannot erase an
effect from a reusable unhandled interface. Executing a callback zero times does
not skip required source checking.

## Lexical captures and canonical inputs

Capture slots follow immutable Core capture order and identify the binding
version captured at closure creation. They include non-generalized type/row
relationships and alias classes. Rebinding a source name cannot change an
already-created closure's capture. Two slots denoting the same captured object
must retain that alias relationship after import.

Type-only principal information can omit ordinary runtime scalar bits when those
bits were not observed during checking. A selected judgment must include every
value, body, nominal identity, generative identity, provider identity and alias
relationship capable of changing its decisions. If the analysis cannot enumerate
those observations, decline independent sharing. Captured demands also
distinguish creation identity and any memo state actually consumed by staging; a
type summary grants no permission to reuse evaluated demand results.

Canonical specialization keys contain:

1. Summary schema, mode, semantic options and complete body/component identity.
2. Alpha-normalized complete type, row and evidence graphs, preserving sharing
   and recursive backreferences where allowed.
3. Ordered captures, their alias partition and all observed value dependencies.
4. Ordered selected implementations, catalogs, nominal/generative/provider
   identities and principal row-closing decisions.
5. Any expected result or staging input consumed by this judgment.

Canonical binder numbering follows interface/capture traversal and stable field
order, not allocation order. Nominal and provider identity is never alpha
renamed into equivalence. Hashes select candidates; exact graph equality and
dependency validation decide reuse, including under forced hash collisions.
Witness spans and final Wasm function indices are not semantic inputs. The key
certifies a semantic judgment, not unchanged executable behavior or values.

## Recursive components and bounded scheduling

Discover directed edges among known callable body identities using an explicit
work stack. Calls through formal unknown callbacks become `CallbackUse`
obligations; they are not speculative edges to every possible body. Compute
strongly connected components iteratively. If resolving a known callback or
selected implementation adds a recursive edge, merge affected components and
discard their tentative results before continuing. Do not publish any member
before the component's boundary stabilizes.

One component uses one joint chronological solver region. Each member starts
with its checked declared scheme, or the same monomorphic recursive placeholder
that ordinary checking would use. Internal edges add relationships to that
region. Acyclic external edges consume summaries through separate jobs.
Unannotated polymorphic recursion gains no new inference rule: preserve ordinary
acceptance, required annotations and rejection behavior.

Process newly affected obligations with a worklist until the component reaches a
fixed point. Existing type depth, value/node/edge storage and occurs-check
limits apply. Add a summary transition budget to `Options`, defaulting to
1,000,000 per top-level inquiry, counting graph discovery, component merges and
solver scheduling transitions. Include it in option equality and dependency
identity. Budget exhaustion declines speculative sharing and allows the ordinary
bounded checker to supply the authoritative limit diagnostic. Fallback must also
use explicit scheduling; it cannot reintroduce a native call-stack cliff on a
deep acyclic chain. Executed evaluation retains its separate `max_steps` and
`max_depth` limits.

States are `queued`, `running`, `waiting`, `complete` and `declined`. `open` is
a caller-side request outcome, not a globally cached negative result. Waiting
jobs resume only after a dependency changes. A repeated request for the same
complete key joins its existing ticket. Declined results are scoped to that
exact key, mode, options and dependency version. Out-of-memory is an error,
never a cached semantic decline.

## Diagnostics, ownership and publication

Speculative jobs publish no user-visible diagnostics. Retain only bounded
decline reasons for profiling. On a failed or unsupported judgment, replay
ordinary checking with the use's original witness map, deferred-member context,
source admission policy and traversal order. Result-directed failures retain
their result origin. Unused source checking and reachable code checking keep
their existing separate responsibilities.

Source-order diagnostics must match the sharing-disabled path even when
independent jobs finish in another order. Store obligation ordinals from normal
collection and report through the authoritative traversal. A component failure
does not expose a later leaf error ahead of an earlier caller argument error.
Failed-edit correction must not retain either diagnostic buffers or a declined
entry with stale dependencies.

Each job owns its solver, import maps, worklists and temporary graph builder.
Scratch addresses, solver IDs, caller frames and borrowed source slices never
enter a published result. Reserve result storage and index capacity before
publication, copy or transfer the complete graph to its durable owner, validate
dependencies, then atomically install the visible handle. Rollback releases all
tentative owners and leaves the previous complete result usable.

All members of a recursive component publish together. An independently checked
acyclic callee may publish before an enclosing caller completes and remains
usable if that caller later fails. A successful sub-step of a failed component
is not an independent proof. Session teardown, cancellation and allocation
failure release waiting jobs and result leases exactly once.

The initial implementation is session-local. Existing dependency/checkpoint
formats must not serialize raw summary or solver IDs. Portable summaries require
the later versioned query/artifact format, owner reconstruction, identity and
bounds checks. Unsupported or incomplete records fall back to source checking;
an older compiler identity cannot validate a newer summary schema.

## Acceptance examples for the implementation sequence

These are required tests, not claims of implemented support. Each group needs
native laws, executed-Wasm coverage, sharing-disabled diagnostic comparisons,
allocation-failure recovery, and fresh/retained/dependency/checkpoint coverage
where the relevant representation is supported.

| Work                        | Positive case                                                                                                                                                         | Negative case                                                                                                                       | Recovery and measurable boundary                                                                                                                                                               |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Predicate-bearing summaries | Generic `twice x = x + x`, nested `Box.add`, record fields and a repeated diamond share predicates by graph edge; U32/F32 and nominal instances select independently. | Mixed operands, absent members and incompatible result-directed constructors fail at the original witness in the same order.        | Fix the leaf in a retained revision; unaffected completed callees survive an unrelated caller failure. Deep chains and diamonds grow with distinct nodes/edges, not paths.                     |
| Higher-order summaries      | A reducer using `step accumulator element` admits pure and effectful callbacks with their exact rows; a callback returning a callback preserves both interfaces.      | Incompatible callback results and an unhandled effect remain rejected; unused invocation paths do not erase source obligations.     | Change the callback or provider without changing its apparent scalar result type; the relevant judgment rechecks. The sandbox no longer needs the entire acyclic callback graph in one region. |
| Lexical summaries           | Two closures sharing a captured aggregate preserve aliases; a closure created before rebinding still sees its original capture.                                       | Same body and capture types with different observed staged values/providers cannot share a selected result.                         | Edit only a capture or alias graph, fail publication under OOM, then retry. No stale capture evidence is imported.                                                                             |
| Recursive components        | Mutually recursive annotated even/odd functions and a recursive diamond use one bounded region per component; independent leaves remain separate.                     | An ill-typed recursive leaf and unsupported unannotated polymorphic recursion preserve ordinary diagnostics.                        | Fix a member after a failed component, exercise budget exhaustion and a 1,000-function acyclic chain. No partial member is published and native stack depth is bounded.                        |
| Canonical specialization    | Separately allocated but equal complete body/evidence/capture graphs request one semantic region.                                                                     | Different nominal identities, provider instances, captured aliases, staging inputs or selected evidence never collide semantically. | Force hash collisions, reorder allocation, and repeat retained/imported requests. Counters show no duplicate region for the same admitted complete canonical key.                              |

Concrete source examples use the existing guide syntax:
`const twice = fn value
=> value + value`; a reducer accepts
`fn accumulator => fn element => ...`; effects use `use` and `@effect.provider`;
recursive functions use ordinary named `fn` bindings. No new annotation or
declaration syntax belongs to this feature. The full
[language guide](../compiler/guide.md) remains authoritative for syntax,
dispatch order and source admission.

Record summary requests, principal hits, judgment hits, deferred imports,
declines by bounded reason, component sizes, graph nodes/edges and scheduling
transitions. Profile largest-region time separately from total compiler CPU and
allocation. The under-50-ms largest-region and no-duplicate-key targets remain
implementation qualification gates; a design or a narrower admitted subset does
not satisfy them.

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

## Predicate-admission experiment, 9 October 2026

The isolated admission-graph experiment is not production. It allows explicit
dispatch, field and update obligations through the existing first-order job
queue. It classifies reachable callee requirements once and propagates declined
requirements through reverse edges, rather than repeating a transitive walk for
each target. Signature shape admission remains separate from that graph cache.
This does not implement the principal graph, result-directed inputs, general
predicate coverage or the transition budget specified above.

The baseline release is the sequential List traversal compiler at commit
`bcff12b47611020d4effd9a5eb8d0b97c1835c55`, SHA-256
`742c3e91faf3dd682d33873d8d02da13eefa0f252c62da570c3fb3b0bc068053`. The
experiment's release SHA-256 is
`39d34414fea6cf173cc9538ffd92f8609267208f1107e220f27c620118b8e79e`. Its patch is
preserved in `build/bench/call-summary-graph-prototype/source.patch`; release
inputs, commands, samples and results are in
`build/bench/call-summary-graph-release/`. Private workload sources remain
uncommitted.

Sixteen existing execution tests passed, covering deep chains, callbacks,
effects, qualified rows/evidence, contracts, dependencies, checkpoints and
retained failure recovery. Eighteen diagnostic-boundary cases at depths 0, 16
and 128 preserved the exact ordered diagnostics for missing fields, incompatible
results, competing failures and annotation witnesses. Deferred unused failures
remain accepted as in the baseline. Twelve synthetic cases at depths 0, 16, 64
and 128 preserved outcomes, diagnostics and Wasm bytes across seven alternating
pairs; every compiler teardown reported zero live bytes.

The successful deep chains show why smaller regions alone are insufficient:

| Chain, depth 128                 | Largest region, scopes | CPU, ms | Requested allocation, bytes | Solver visits |
| -------------------------------- | ---------------------: | ------: | --------------------------: | ------------: |
| Associated predicate, baseline   |                    260 |  10.242 |                   5,406,388 |         1,569 |
| Associated predicate, experiment |                      2 |  11.716 |                   8,803,028 |         2,859 |
| Field predicate, baseline        |                    130 |   9.171 |                   5,135,019 |           393 |
| Field predicate, experiment      |                      1 |   9.775 |                   8,555,007 |         1,425 |

The failing associated chain improved from 7.471 to 5.876 ms and from 4,599,745
to 4,136,869 requested bytes. That improvement does not offset the successful
chains' increased allocation and solver work or establish complete admission.

Seven alternating gdev pairs without restart caching measured 791/790 ms fresh
CPU, 900/910 ms dependency population, 200/200 ms first edit and 180/180 ms
subsequent edit, baseline/experiment respectively. Fresh requested allocation
was 321,026,930/321,060,278 bytes. In a separate restart-cache batch the medians
were 853/846 ms cold population, 495/480 ms restart, 890/910 ms dependency
population, 190/200 ms first edit and 180/180 ms subsequent edit. No-op CPU was
below the retained process counter's 10 ms resolution. All same-compiler and
cross-compiler Wasm comparisons passed without an exception flag; gdev work
counters were unchanged. Host load fell from about 25.5 to 15.5 on 16 CPUs, so
these are paired loaded-host observations, not idle-machine qualification.

Decision: do not land this admission expansion. Keep the graph and diagnostic
cases as evidence for the next implementation. It must represent residual
requirements and share principal work without multiplying successful job
allocation, and still supply bounded scheduling, authoritative fallback and
allocation-failure coverage. Task 004 remains open.

## Written-predicate scheme milestone, 9 October 2026

The follow-on candidate imports the already checked, written requirements of a
declared first-order global function into a fresh region scope. It retains the
ordinary source argument witness mapping and solves those predicates before
publishing a closed judgment. It does not recollect the declared body for every
use. Predicate-free admission is unchanged; inferred predicates, selected-mode
capture retention, complete demand-body checking and higher-order shapes keep
their existing paths. This is a bounded part of task 004, not its completion.

The isolated release has SHA-256
`d46f5bda8ea02630366467ac8028d34b304361bab1c033c0269589db8d021775`. Its native
suite and all 596 guest/client tests pass, as does the analyzer across 287 files
with zero findings. The new native law checks immutable Core and exhaustive
allocation failures while requiring bounded source-interface region size. The
new execution law checks independent U32/F32 instantiations through imports,
dependency bundles, checkpoints, body edits, rejected edits and recovery.
Seventeen focused execution laws, eighteen diagnostic-boundary cases and 305
corpus cases (610 invocations) also pass without diagnostic or Wasm differences.

Seven alternating synthetic pairs measured these depth-128 cases:

| Chain                | CPU, baseline/candidate ms | Requested allocation, baseline/candidate bytes |
| -------------------- | -------------------------: | ---------------------------------------------: |
| Associated predicate |             10.153 / 9.384 |                          5,406,379 / 4,740,399 |
| Field predicate      |              8.443 / 8.411 |                          5,135,010 / 4,619,098 |
| Missing evidence     |              7.213 / 6.274 |                          4,599,736 / 4,136,616 |

The associated chain's largest source-interface region falls from 260 to 4
scopes, and the field chain's from 130 to 2. Successful job counts do not
multiply. A separate seven-pair, 98-request retained probe covers population,
failed edits, repeated failure, recovery, valid body edits, restoration and
no-op requests. Diagnostics and Wasm remain stable; guest results are checked.
Most small retained phases are below or near the 10 ms CPU accounting
resolution, so this probe establishes recovery, not a gdev speedup.

The first full-gate attempt in the isolated checkout stopped at guest type
checking because that checkout lacked unchanged host modules and parser assets.
After restoring those files from the repository, the exact full command passed.
Only `build/bench/explicit-scheme-release/compiler-gate-restored.log` is passing
full-gate evidence for that isolated release. Raw samples, diagnostics, source
patches and recovery records are in that directory.

The production-tree candidate, including the future-alias fix, is SHA-256
`4484ea5b46e30cd6c6b8b66fc8855098893a99c74a1a4d3cd4bf4019cadecf3b`. Seven
alternating gdev pairs measure 942/953 ms cold CPU, 1,090/1,100 ms population,
250/250 ms first edit and 220/220 ms subsequent edit. A separate restart batch
measures 1,027/1,026 ms cold population, 645/649 ms process restart, 1,090/1,090
ms retained population, 240/240 ms first edit and 220/220 ms subsequent edit.
No-op CPU remains below the 10 ms accounting resolution. All byte comparisons
pass; these loaded-host measurements establish no gdev speedup. Raw results are
under `build/bench/written-predicate-main/`. Its combined full compiler gate
passes the native suite and all 596 guest/client tests; the production analyzer
checks 287 Zig files with zero findings. The logs are
`build/bench/written-predicate-main-compiler-gate.log` and
`build/bench/written-predicate-main-analyzer.log`. The written-predicate
milestone is qualified for production. General principal/residual graph
summaries remain unfinished.

## Bounded callee admission, 9 October 2026

The next change retains the existing admitted obligation kinds. It separates the
requested function's first-order shape check from the transitive scheme check,
visits each reachable callee once, and propagates rejection from a child to its
ancestors. A rejected child does not reject an unrelated valid sibling. Node and
edge counts are bounded by the configured value limit, capped at the 32-bit
index range. Reaching the bound declines without publishing a partial
classification. Complete classifications reserve all cache capacity before
publication. The cache belongs to the immutable source Session, and job-local
recursion and active-job checks still run before consulting it.

The isolated release is SHA-256
`1fdac33389d5186e23a526168d2923f7aa776a9ef18e81fec7617726c9daf289`, in
`build/bench/call-admission/`. Its focused native law counts at most 34 visits
for a 32-wrapper associated-member chain, performs no new visits for the same
completed query, and passes exhaustive allocation failures. The counter does not
increment in production. Seventeen execution laws and 305 corpus cases (610
invocations, 244 successful cases) preserve results, ordered diagnostics and
Wasm. The isolated analyzer reports zero findings across 287 files.

Seven alternating synthetic pairs compare against the written-predicate
milestone. At depth 128, associated-chain CPU falls from 9.220 to 8.308 ms and
requested allocation from 7,292,829 to 6,755,861 bytes. Field-chain CPU falls
from 9.886 to 9.375 ms and allocation from 7,272,429 to 6,744,317 bytes. Missing
evidence retains its authoritative diagnostics; CPU measures 31.090/30.447 ms
and allocation 27,633,323/27,096,355 bytes. Smaller CPU cases are mixed.

Seven gdev no-cache pairs measure 966/972 ms fresh CPU, 1,130/1,140 ms
population, 250/250 ms first edit and 240/230 ms subsequent edit. A separate
seven-pair restart batch measures 1,039/1,035 ms cold population, 639/652 ms
process restart, 1,080/1,110 ms retained population, 250/250 ms first edit and
230/230 ms subsequent edit. No-op CPU is below the 10-ms accounting resolution.
All Wasm comparisons pass. These loaded-host measurements establish no general
compiler speedup. The bounded graph scan does not implement principal/residual
graphs, result-directed inputs, lexical captures or higher-order summaries; task
004 and its successor tasks remain open.

The combined production release, including the U32 row-fold pass, is SHA-256
`1a0be8c0a216346299f7701484287f58675a337fce872272bafeec22a9e9c8a0`, pinned in
`build/bench/row-and-admission-main/`. Its full native suite and all 598
guest/client tests pass. The analyzer checks 288 files with zero findings; logs
are `build/bench/row-and-admission-main-compiler-gate.log` and
`build/bench/row-and-admission-main-analyzer.log`. Three additional integration
pairs preserve all fresh/retained/restart byte comparisons. The independent
seven-pair admission measurements above remain the better isolated cost record.

## Result-directed expected-input experiment, 9 October 2026

An isolated candidate admits first-order result-directed predicates only when
the entire expected call signature projects to closed evidence. That signature
joins the argument evidence and checking mode in the job key; an open result or
effect row retains ordinary caller-side checking. Transitive admission records
whether a descendant needs this complete expectation. Job construction imports
the keyed signature into its own solver before collecting the body. This is a
closed call judgment, not principal information.

The release pin is
`af8afe6f77f5406008d9597707a2e489ee59facb9b3afced150c1fe767174d0e`, in
`build/bench/result-call-summaries/`. Focused native laws prove that U32 and F32
expectations receive distinct complete jobs and repeated identical uses share
one job. Immutable-input and exhaustive allocation-failure checks pass, as do
the existing contextual-result laws. The analyzer reports zero findings in 287
files. Eighteen execution laws pass, including imports, dependency bundles,
checkpoints, repeated failed edits, recovery and changed bodies. All 305 corpus
comparisons preserve semantics, ordered diagnostics and Wasm.

Seven depth-128 synthetic pairs expose a cost that prevents acceptance. The U32
result chain grows from 5,029,133 to 6,468,129 requested bytes and from 8.406 to
9.034 ms CPU; the F32 chain grows from 5,029,136 to 6,468,132 bytes and from
7.712 to 8.539 ms. The U32 chain's largest region shrinks from 133 to 3 scopes,
but total regions rise from 134 to 394 and solver passes from 138 to 919. The
total scope count remains 401. More independent jobs do not remove the repeated
work.

Seven gdev pairs measure 938/1,080 ms fresh CPU and 1,110/1,240 ms retained
population, baseline/candidate. First edits measure 250/240 ms and subsequent
edits 230/230 ms. The restart batch measures 1,067/1,191 ms cold population,
644/644 ms restart, 1,100/1,230 ms retained population, 250/260 ms first edit
and 230/230 ms subsequent edit. All byte comparisons pass. These loaded-host
results reinforce the rejection: the fresh/population increase is material. The
candidate remains unlanded, and no full compiler gate or completion claim is
made for it. Its source patch, execution test and raw samples remain in the
qualification directory for work on the principal graph representation.

## Dispatched written-predicate schemes, 9 October 2026

Commit `f7be6e7` extends the written-predicate milestone. Type-only selection
now uses the existing checked written-scheme import for associated
implementations, member implementations and constructors selected by result
type. `callableScope` has already imported the implementation's root and
residual predicates into a fresh scope. `collectSelected` can retain that
instance without collecting its body again when the existing first-order global
admission rule accepts it. Each residual must still solve before proof
publication. The receiver/result relationships, invocation rows and
qualification origins stay in the caller's solver. The source receipt records
the selected implementation so body edits invalidate it.

The early guard keeps selected capture/emission and complete demand-body
checking on their original body collection path, without an additional scheme
lookup. Predicate-free implementations, unsupported residuals and higher-order
shapes also keep their existing paths. No new principal facts, independent jobs
or result-directed cache key are created. This extends the qualified written
milestone; it does not implement general inferred/residual graphs or finish task
004.

The baseline is source revision `65dccda`, release SHA-256
`745347b7752831e4bae78397f5e3731ab8e16d0d227314ee2afd8d399c1baf82`. The final
candidate is SHA-256
`d431170c3bfa2c3dd38b5c61eff375a6e326b3a530e14896b9a8e0873869f439`. Both use Zig
0.17.0. Binaries, identities, source patch, generated public workloads,
comparisons and raw measurements are preserved in
`build/bench/cloud-selected-schemes/`.

Qualification includes the full `deno task test:compiler` command (native suite
and 600 guest/client tests), and `deno task lint:zig` (zero findings across 290
Zig files). The native law checks separate U32/F32 argument and result
instantiations, bounded source regions, immutable Core/type/obligation tables
and exhaustive allocation failures. Its focused test binary executes the law as
well as the fifteen discovery tests. The import law covers dispatched physical
fields, members, associated calls and result-selected constructors through
dependency bundles, checkpoints, body edits, failed edits and recovery. A
curried member law executes its implementation's handled operation and rejects
an unsatisfied extra residual.

The differential command `python3 build/bench/cloud-selected-schemes/compare.py`
compares 367 public cases (734 compiler invocations), including tracked sources
in both prelude modes and generated dispatch/diagnostic cases. All ordered JSON
diagnostics and successful Wasm bytes match; 250 cases succeed. The remaining
cases include missing associated/field/receiver evidence, incompatible results,
open representation predicates, unused qualifications and ordered failures.
Every emitted compilation memory record reports zero live bytes; two intentional
type-limit cases emit only matching diagnostics.

Seven alternating fresh-process pairs cover 24 generated
associated/member/result cases at depths 0, 16, 64 and 128, including 8/32
repeated body calls. All preserve Wasm. Requested allocation falls by 304–36,888
bytes; each case has two fewer total scopes and four fewer constraint visits,
with unchanged region and solver-pass counts. The command is
`python3 build/bench/cloud-selected-schemes/measure.py`; the initial load is
about 0.18. A separate 31-pair run (`measure_main.py`) gives these depth-128
medians and the same deterministic allocation/scope counts:

| Case                  | Child CPU ms, baseline/candidate | Requested allocation bytes, baseline/candidate | Largest region scopes, baseline/candidate |
| --------------------- | -------------------------------: | ---------------------------------------------: | ----------------------------------------: |
| Associated, depth 128 |                    4.833 / 4.796 |                          2,338,914 / 2,306,130 |                                     5 / 4 |
| Member, depth 128     |                    4.529 / 4.879 |                          2,281,312 / 2,263,416 |                                     7 / 5 |
| Result, depth 128     |                    4.656 / 4.574 |                          2,272,425 / 2,254,529 |                                     7 / 5 |

CPU is mixed: the member example is slower despite its reduced work and
allocation. The separate 31-pair fan-out probe measures 16.028/16.322 ms child
CPU, with a median paired ratio of 1.009. These observations are not a general
speedup claim.

Seven
`deno task bench:compile --baseline build/bench/cloud-selected-schemes/baseline/blotc --candidate build/bench/cloud-selected-schemes/candidate/blotc --runs 7 --workload synthetic --out build/bench/cloud-selected-schemes/synthetic`
pairs preserve fresh/retained Wasm equality across population, first edit,
subsequent edit/revert and no-op phases. Fresh CPU medians are 8/8, 7/7, 5/4 and
15/15 ms for monomorphic chain 128, generic chain 64, diamond 8 and fan-out 128.
Retained timings often fall below the 10-ms process-accounting resolution. Load
rises from about 0.2 to 0.4. This establishes execution/recovery parity, not a
retained CPU improvement.

The frozen private gdev snapshot is unavailable in this cloud checkout. These
public comparisons do not replace gdev qualification or establish a general
compiler CPU speedup. The initial guard placement is preserved separately under
`initial-candidate/` and `initial-results/`; the final guard avoids its emission
lookup. General principal/residual graphs, unsupported explicit/result-directed
requirements, higher-order inputs and component handling remain open.

## Owned inferred principal graphs, 9 October 2026

Commit `099e700` describes each admitted global first-order body once in an
immutable Session-owned graph. It retains the interface, type and row binders,
ordered body constraints, aliases, function relationships and global callee
edges. Each edge keeps its original argument expressions and deferred-member
context. Import creates fresh caller-local binders, preserves sharing inside
that import and replays the original action order. Source Core/type/obligation
tables remain immutable. No live solver address or caller-selected proof enters
the graph owner.

Description collects one body without expanding its callees. It publishes only
after every owned array and cache allocation succeeds. Graph nodes and edges,
including diagnostic spelling storage, count against the Session's configured
value/child limits. Allocation failure remains an error. Descriptions with
chronological writes, rigid row parameters, lexical/value-dependent forms or
unsupported first-order shapes decline to ordinary collection. Small quota
inquiries, selected captures/emission, complete demand checking and independent
closed-input jobs retain their original paths.

An optional principal/source-interface inquiry can export an unresolved callee
edge when its complete interface has only unknown data binders and unselected
rows. An iterative scan checks every distinct reachable body and edge, preserving
diamonds rather than copying their transitive paths. Explicit requirements,
concrete bounds, structured endpoints and recursion decline this shortcut. The
edge remains unsolved; it cannot publish a complete validated-call judgment or a
dependency-complete refinement receipt. A later concrete caller input, result or
row uses the ordinary solver and witness path. The closed-input job key is
unchanged. General result-directed callee admission and unsupported explicit
requirements remain task 004 work; this milestone does not complete that task.

The baseline is the qualified `f7be6e7` release, SHA-256
`d431170c3bfa2c3dd38b5c61eff375a6e326b3a530e14896b9a8e0873869f439`.
The candidate is SHA-256
`ae2458cb3e31cd42f2f9c91a40909ff43786474aff2a28f33d9b009e0688bbaa`, with
compiler-identity file SHA-256
`dc5b861ddb9628c6f32bc402d4dc5d22943c91635262c135aa954f8ddfcfa225`.
Both use Zig 0.17.0. The four-file source patch is SHA-256
`22686519b212babe27347a6f68e13b61b646e944f54350e2ab7f6e0b50fa708b`.
Pins, generated sources, scripts and raw results are in
`build/bench/cloud-principal-graphs/`; the final pin is `candidate-guarded/`.
Earlier candidate directories preserve investigations and are not this release.

Qualification commands and results:

- `deno task test:compiler`: full native suite and all 601 guest/client tests
  pass; `compiler-gate-factory.log` records the final run.
- `deno task lint:zig`: 291 Zig files, zero findings, using the CI-pinned
  analyzer; `analyzer-guarded.log` records the run.
- `python3 build/bench/cloud-principal-graphs/compare-guarded.py`: all 393
  public cases match ordered JSON diagnostics and successful Wasm bytes, with
  276 successful cases. Compilation memory records return to zero live bytes.
- Native laws check independent U32/F32 imports, repeated queries, immutable
  source tables and exhaustive allocation failures through description, graph
  copying, traversal and publication. Open diamonds at depths 8, 16 and 64
  have work bounded by distinct bodies/edges and perform no evaluation.
- The new executed-Wasm law uses a staged factory, a repeated diamond and a
  result-selected constructor through an import. Fresh and retained builds
  agree after body edits, a failed edit and correction. Existing dependency,
  checkpoint, callback/effect and diagnostic laws also pass the full gate.

The factory workload returns a generic helper from a `do` constant, triggering
the optional principal inquiry before independent U32/F32 use. Its leaf calls
ordinary associated `add`; each wrapper calls its predecessor twice. Fifteen
alternating fresh-process pairs disable persistence, verify exact Wasm equality
and zero live bytes, and measure child user plus system CPU with `getrusage`.
The command is
`python3 build/bench/cloud-principal-graphs/measure-guarded-factory-three.py`.
Host load is approximately 0.89 on five reported CPUs. Requested allocation and
work counters are identical across repetitions of each binary.

| Diamond depth | Median CPU ms, baseline/candidate | Requested allocation bytes, baseline/candidate | Total scopes, baseline/candidate | Largest region scopes, baseline/candidate | Constraint visits, baseline/candidate |
| ------------: | --------------------------------: | ---------------------------------------------: | -------------------------------: | ----------------------------------------: | ------------------------------------: |
| 4             |                     4.486 / 4.338 |                          3,602,120 / 3,474,384 |                          82 / 56 |                                    32 / 3 |                             191 / 130 |
| 8             |                     7.219 / 4.689 |                          5,420,870 / 4,158,718 |                         586 / 84 |                                   512 / 3 |                           1,255 / 234 |
| 12            |                   198.730 / 5.371 |                         19,420,315 / 4,783,635 |                      8,290 / 112 |                                 8,192 / 3 |                          16,719 / 338 |

Description regions are included: at depth 12 total regions rise from 87 to
100 while unresolved body collections fall from 8,195 to 4. This is a measured
improvement for the staged factory inquiry. Ordinary typed workloads need not
invoke that inquiry and do not acquire the same reduction. The extended
depth-16 fresh batch was stopped after one pair because baseline checking was
slow; its raw files are preserved separately and excluded from these medians.

Seven official synthetic pairs compare fresh, retained population, first edit,
edit/revert, no-op and restart phases:
`deno task bench:compile --baseline build/bench/cloud-selected-schemes/candidate/blotc --candidate build/bench/cloud-principal-graphs/candidate-guarded/blotc --runs 7 --workload synthetic --restart-cache --out build/bench/cloud-principal-graphs/guarded-synthetic`.
All byte comparisons pass. Ordinary monomorphic/generic chains, diamond 8 and
fan-out 128 retain their deterministic work counters. CPU is mixed; retained
samples frequently fall below the 10-ms accounting resolution. The frozen
private gdev snapshot remains unavailable, so these public results establish no
general compiler or gdev speedup.

The same seven-pair harness, extended with the factory source and its ordinary
leaf edit, also passes all fresh/retained/restart comparisons:
`deno run --allow-all build/bench/cloud-principal-graphs/bench-compile-factory.ts --baseline build/bench/cloud-selected-schemes/candidate/blotc --candidate build/bench/cloud-principal-graphs/candidate-guarded/blotc --runs 7 --workload factory_diamond_12 --restart-cache --out build/bench/cloud-principal-graphs/guarded-factory-retained`.
Fresh CPU is 205/7 ms; retained population, first edit and subsequent edit are
200/<10, 210/<10 and 190/<10 ms. Restart is 7/7 ms and no-op is below 10 ms for
both. The retained factory improvement is above the accounting resolution;
the candidate's sub-10-ms samples do not provide a more precise latency.

# Typed staging qualification

Tasks 067/068 remain in progress. The ordinary frontend, immutable Core and
evaluator own the admitted code/descriptor graphs; no generated strings or
second frontend are used. Focused results below do not establish release or
performance qualification.

## Trace-to-law index, 17 October 2026

This index maps the seven acceptance traces that the owner fixed for tasks 067
and 068 on 15 October 2026 to named laws in the passing gate at commit `05401a9`
(17 October 2026: 2,355 native laws with zero leaks, 1,501 guest tests). Every
law named below appears in that gate output and is declared in the committed
source. Paths are relative to `zig-native/`. Five traces are fully covered; two
067 traces are only partly covered, as noted under them.

Tasks 067 and 068 remain open. The traces' closure also asks for measured and
recorded population and retained costs. The only recorded cost screen is the
three-pair development screen of 14 October
([generic helpers](#generic-helpers-and-nominal-lifts-14-october-2026)), which
predates the 15 October stage-owner continuation and the gated source.

### 067: Quote calls an imported opaque operation

Expected: Preserve its original abstraction/evidence. Coverage: complete.

```text
native src/check/frozen_core_validation_tests.zig: portable typed staging retains sealed package identities and stored operations
native src/reuse/semantic_archive_tests.zig: persisted typed staging seals package recipes and never exposes cached bound descriptors through OOM
native src/check/frozen_core_validation_tests.zig: portable typed staging admits named operation calls and rejects forged pure claims
guest  tests/typed_staging_sealed.test.ts: quoted opaque operations preserve abstraction through imports and restart (consumer quote: false)
guest  tests/typed_staging_sealed.test.ts: quoted opaque operations preserve abstraction through imports and restart (consumer quote: true)
guest  tests/typed_staging_packages.test.ts: quoted heterogeneous sealed packages preserve descriptor shape stored operations hygiene and restart
```

### 067: Splice a different result/effect/usage shape

Expected: Reject at splice site. Coverage: partial. Result shapes (a Bool splice
into a U32 operand, `type_mismatch`) and effect rows (`effect_mismatch`,
`const_effect`, unrelated row certificates) have named laws. No named law
splices code whose usage qualifier differs from the expected shape.

```text
native src/check/typed_staging_tests.zig: typed staging rejects bare earlier values malformed shapes and authority crossing
native src/check/typed_staging_tests.zig: typed staging row widening retains missing handlers callback rows and pure run restrictions
native src/check/frozen_core_validation_tests.zig: portable typed staging never closes splice rows using an unrelated body certificate
native src/check/frozen_core_validation_tests.zig: portable typed staging validates complete shapes and rejects forged operands and stage references
```

### 067: Lift a resource or descriptor for a live scope/skolem

Expected: Reject before publication. Coverage: partial. Callable authority,
affine nominal/opaque payloads, scoped capabilities and escaping loans reject
with named laws. No named law quotes or lifts a value whose type mentions a live
skolem (the checker's `rank_walk` path that reports `cross_stage_authority`).

```text
native src/check/typed_staging_tests.zig: typed staging rejects bare earlier values malformed shapes and authority crossing
native src/check/usage_check_tests.zig: usage nominal affinity cannot be lifted across a stage through an opaque payload
native src/check/usage_check_tests.zig: usage nominal repeatable owners still carry lifetime authority across lift and package boundaries
native src/check/frozen_core_validation_tests.zig: portable typed staging refuses scoped authority hidden in quoted closure capture tables
native src/check/frozen_core_validation_tests.zig: portable typed staging loan captures reject phantom missing and escaping executable owners
guest  tests/typed_staging_execution.test.ts: nominal lifts reject hidden callable payloads before publication
```

### 068: Two emissions each bind a local `value` beside a caller `value`

Expected: Three distinct lexical identities. Coverage: complete.

```text
native src/check/typed_staging_tests.zig: typed staging checks owned shapes stage locals and explicit composition through OOM
native src/check/frozen_core_validation_tests.zig: portable typed staging helper locals reject future reads caller capture duplicate owners and foreign returns
guest  tests/typed_staging_execution.test.ts: repeated typed-code emissions preserve independent locals beside caller bindings
guest  tests/typed_staging_execution.test.ts: imported typed generators preserve hygiene retained edits failures and restart
guest  tests/typed_staging_statement_if.test.ts: staged statement if helpers preserve branch hygiene source archive edits recovery and checkpoint restart
```

### 068: Asset bytes change, type remains U32

Expected: Rerun tracked generator and affected executable users. Coverage:
complete.

```text
native src/check/frozen_core_validation_tests.zig: typed staging declaration projection retains exact inputs and invalidates same-type quoted edits
native src/reuse/principal_reuse_gate_tests.zig: principal gate invalidates direct and transitive staged declaration dependencies
guest  tests/typed_staging_execution.test.ts: typed generators track exact host asset bytes through edits failures and restart
guest  tests/typed_staging_execution.test.ts: imported staging tracks fixed-type inputs and future bodies across independent expansions
```

### 068: Generator fails after allocating a partial graph

Expected: Keep prior code/assets usable; release candidate owners. Coverage:
complete.

```text
native src/reuse/revision_input_tests.zig: revision input backend staging failure after fresh dependency freeze retains published old owners
native src/reuse/principal_input_tests.zig: principal input image does not hide staged errors or change the last good capture
native src/check/typed_staging_tests.zig: typed staging owns composed graphs after frontend teardown through OOM
native src/check/frozen_core_validation_tests.zig: portable typed staging owns roundtrip graphs after producer release through allocation failures
guest  tests/typed_staging_execution.test.ts: imported typed generators preserve hygiene retained edits failures and restart
guest  tests/typed_staging_execution.test.ts: typed generators track exact host asset bytes through edits failures and restart
```

### 068: Restart from dependency/checkpoint code records

Expected: Same bindings, bytes, source fuel and failure behavior. Coverage:
complete.

```text
native src/reuse/semantic_archive_tests.zig: persisted typed staging validates code owners replacements descriptors and restart through OOM
native src/reuse/semantic_archive_tests.zig: persisted generated origins own exact source nodes and reject forged catalogs through OOM
guest  tests/typed_staging_execution.test.ts: imported typed generators preserve hygiene retained edits failures and restart
guest  tests/typed_staging_origins.test.ts: generated diagnostics retain the selected generator through imports records and recovery
guest  tests/typed_staging_composition.test.ts: named stateful requests preserve lexical owners source archive edits recovery and checkpoint restart
```

## Current continuation, 15 October 2026

The current focused batches pass 60 portable staging native laws, including
complete allocation failures, forged local/capture/row owners, missing foreign
producers and future double moves. It adds loop carries and mutable merges,
fresh scope/provider execution and capture edges, latent closure effects,
ordinary row-polymorphic call principals, named provider callbacks and isolated
future affine parameter ownership, lexical loan callback regions and resource
cleanup ownership. Resource acquisition, release and scope callbacks retain
their actual Foreign effect and reject forged cleanup qualifiers or erased
effect rows.

Direct request loops retain their producer's declared operation signature and
the actual computation, clause and enclosing row owners. A smaller computation
row uses ordinary variance; unused handlers do not execute. Erased rows and
forged declaration signatures reject. Checker publication resolves the owned
computation/request metadata before Core projection.

Lift and splice operands now use their actual earlier-stage move/loan
environment, including nested quotes. Their moves propagate back to that owner.
A once generator captures construction inputs without adding earlier values to
future lambda capture tables. Qualified scalar constants retain their usage
evidence; their construction declines constant receipts.
Direct/nested/spliced/once generation passes portable roundtrip and exhaustive
allocation failures, and a forged repeated earlier move rejects.

Six helper guest recipes pass source/archive/checkpoint/cache restart, edits,
failed revisions, independent emissions, both codegen tiers and sync/JSPI.
Row-principal helpers use 31 source steps and scope-provider helpers use 57;
unchanged/recovered builds use zero. A separate future-usage guest transfers a
unique result and rejects its second use in sync/JSPI. Its generated callable
has an explicit affine declaration; an unannotated unknown callable still
rejects. Two independent loan emissions return their borrowed values. Four
ordinary usage controls also pass. Resource guests cover actual JSPI suspension,
independent emissions, cleanup failure/recovery, bounded memory, source/archive,
edits and cache/checkpoint restart in both tiers. Consumer quotations calling
imported opaque operations preserve abstraction through the same revision paths.
The selected analyzer closures have zero findings. Logs and exact focused source
images: `build/bench/finish-rest-20261015/staging-completion/`.

The combined stage-owner focus passes 73 native laws (60 staging, one operation
header, eleven task controls and one usage control), 25 executed guest groups
and 413 selected analyzer files with zero findings. Both-tier source/archive/
cache/checkpoint edits and recovery include actual JSPI suspension, unused
request clauses, independent emissions and earlier-stage affine generation.
Exact source/binary pins and preserved failed attempts:
`build/bench/finish-rest-20261015/staging-stage-owners/` and
`staging-operation-headers/`.

General named pattern/request/resolver helpers, captured loans and general
resource captures, general qualified producer transport and generation cost
qualification remain open. The older sections below record historical frontiers,
not current bans on repaired forms.

The 15 October statement-`if` recipe closes a source/dependency-export mismatch
for pure helper suites. Both branches independently retain lexical locals and
the enclosing block return target; unselected effects, branch leaks, forged
types and foreign returns reject. Mutable merge owners remain unsupported. Six
integrated native laws pass, including complete portable evaluation and
checkpoint-restart allocation sweeps (1,065 faults including the existing block
neighbor). Twelve selected helper/staging guest groups pass in both tiers with
source/archive/cached/checkpoint restart byte parity. Fresh/edit/restart uses 31
work steps; unchanged/recovered input uses zero. The 236-file affected analyzer
closure is clean. Exact four-file delta, compiler/source pins and logs:
`build/bench/finish-program-20261014/staging-statement-if/`. Tasks 067/068 and
the final full gate remain open.

The next Bool-case recipe uses existing Core pattern metadata and the same
reader for both arm bodies. Exactly one Bool subject and two disjoint canonical
1/0 patterns are admitted; guards, binds, general patterns, statement matches
and mutable merges remain closed. Eleven independent pattern/result/owner
mutants and coordinated unselected effect-row forgeries reject. Seven staged
native laws pass, including complete portable and semantic restart sweeps; four
numeric-rank controls and eleven combined guest groups also pass. Both tiers
preserve source/archive/checkpoint/cached restart bytes and 30 work steps;
statement-if remains 31, unchanged/recovery 0. The affected 236-file analyzer
closure is clean. Exact delta and root logs:
`build/bench/finish-program-20261014/staging-bool-case/`. This closes another
live-source/export mismatch without a new interpreter, schema or cache. General
staging and final qualification remain open.

## Focused frontier, 14 October 2026

Seven [executed staging laws](tests/typed_staging_execution.test.ts) cover
composition, descriptors, local hygiene, rejected stage crossings, delayed
future traps, nested lifts and imported generation. The imported control uses
two scalar inputs from a separate module and three emissions beside shadowed
locals. Fixed-type input edits and quoted executable-body edits match fresh Wasm
and work; an unchanged revision reuses the accepted output with zero native
work. A second expansion failing after the first graph succeeds leaves the prior
Wasm usable. Recovery and restarts after edited inputs/bodies match fresh output
in synchronous and JSPI guests.

The [native descriptor laws](src/check/typed_staging_tests.zig) retain a quoted
closure's exact principal row certificate through frontend teardown and every
allocation failure. Pure and Read-effectful callable descriptors remain
distinct. Contextual row selections take precedence over principal closure
certificates; no unrelated body's certificate is consulted.

[Portable Core laws](src/check/frozen_core_validation_tests.zig) reject forged
code shapes/effects, coordinated call/force signatures, unrelated row
certificates, scoped captures and earlier-stage plain callable capture tables.
[Snapshot laws](src/reuse/semantic_archive_tests.zig) independently compare
source shapes, observed evidence and replacement value graphs. Provider
substitutions, scalar-tag changes without evidence, product cycles, wrong splice
types and forged result/effect rows reject. Unsupported snapshot export omits
the semantic section; checkpoint decode and fresh recomputation retain identical
Wasm. Snapshots without staged values incur no staging allocations.

The callable-descriptor follow-on is pinned by patch SHA256
`e2bce04619c160bb43b60bbc107cfe9c6e1d3cfeda04c4cf7d34a26df895326f`. The focused
development binary SHA256 is
`e8e3d58b464a538702ebcd79714ed1d126e8c3072a470113353edaa185adc25e`. Its bounded
batch ran two native laws in 2.60s and all seven guest laws in 1.18s; the
existing development build was cached. Direct pinned analyzer invocation checked
223 files with zero findings. These iteration timings are not CPU or allocation
benchmark distributions.

Reproduce with Zig 0.17.0, checking `zig version` before the batch:

```sh
TMPDIR=/var/tmp deno task test:compiler:dev \
  --native-filter='typed staging callable descriptors' --native-shards=2 \
  --budget-seconds=60 --phase-seconds=60 \
  --timings-dir=build/bench/staging-callable-descriptor \
  zig-native/tests/typed_staging_execution.test.ts
```

## Qualification gaps recorded on 14 October

- Full compiler gate, local milestone revision and fresh/retained/restart cost
  distributions remain pending. No general speedup is claimed.
- Indirect/effectful future calls and foreign producer references lack exact
  portable instantiation/capture authority; scoped captures remain rejected.
- Private/sealed abstract and package transport, and usage/borrow snapshot
  shapes remain incomplete or conservatively declined. Code results with
  unresolved shapes do not receive a weaker portable certificate.
- Tracked JSON host-asset edits now have an executed revision law below.
- Staged executable fragments conservatively rebuild on changed revisions; only
  existing complete output and semantic admission mechanisms authorize reuse.
  General generated declaration/source-map behavior remains unfinished.

The approved [staging design](TYPED_STAGING.md) remains the target, including
these currently unsupported forms. Focused fixes do not close tasks 053, 065,
067 or 068.

## Exact producer-local named future calls, 14 October 2026

Portable quotes now admit calls to an exact monomorphic, first-order pure body
owned by the same producer module. Admission reconstructs formal and selected
types, every referenced parameter and the executable body. A target body may use
only its own closed-row certificates; a selected call must use its exact
enclosing body or closure certificate. Nested calls repeat that proof. Generic,
indirect, scoped/usage/nominal, effectful and foreign targets remain closed. No
new cache, evaluator or backend path is introduced.

The eleven-law native screen covers producer release, artifact roundtrip,
complete allocation failure and forged signatures, foreign parameters, unrelated
rows and coordinated pure claims over an effectful body. Eight guest groups
cover imported generators, repeated emission, shadowing, helper edits, failed
generation/recovery and restart in sync/JSPI. Fresh, edited and restarted builds
each use 26 source steps; unchanged/recovery output reuse uses zero. Bytes and
execution match independent fresh builds. The same native and guest checks pass
on the rebuilt combined root compiler.

Patch/source/binary pins and logs are under
`build/bench/continuation-20261014/staging-named/` and `staging-named-root/`.
Full combined qualification remains outstanding.

## Generic helpers and nominal lifts, 14 October 2026

Producer-local pure helpers now own up to 32 generic variables. Each call
reconstructs repeated substitutions across scalar, Array/List, tuple and record
positions, then checks the callee body in its own variable scope. Nested calls
share the existing traversal budget. Distinct variable IDs never compare equal
from node contents alone. Higher-order calls, row polymorphism, residual
obligations and authority-bearing shapes still decline this proof.

Ordinary public nominal values may cross an explicit lift. Evaluation checks
every actual payload before installing the quote. A saved snapshot independently
matches its source constructor result to the expected closed nominal type,
admits substitutions only from that constructor and family's own variables,
reconstructs positional/record payload storage and checks every child. Tags,
nominal identities, recursive graph order and observed evidence remain exact.
Private/opaque nominal transport and hidden callable payloads remain rejected.
Ordinary snapshots without staging still allocate nothing for this validation.

The focused Core laws include nested/repeated generic substitutions, producer
release, artifact roundtrip, missing and equal-looking foreign binder mutants,
forged signatures and unrelated effect certificates. Three snapshot laws cover
ordinary allocation cost, staged graph corruption and nominal payload/owner
corruption; complete restart allocation-failure sweeps pass. All twelve executed
guest groups pass in 0.956 s, including imported nominal edit/revert/restart,
generic helpers, hidden callback rejection and tracked JSON bytes. Invalid JSON,
wrong asset types and illegal stage crossings preserve the accepted executable;
corrected inputs match independent fresh builds. The asset and nominal tests
also verify last-good execution after failed edits.

Source copies and the exact six-file delta are under
`build/bench/finish-program-20261014/staging-source/`. Focused logs are
`generic-staging-final-native.log`, `nominal-staging-native-oom.log`,
`staging-neighbor-native.log`, `staging-final-guests.log` and
`staging-final-lint.log` in the same evidence directory. Pinned local lint
checks the 322-file affected closure out of 418 files with zero findings. These
checks await the single final compiler gate and do not establish general staging
or performance completion.

A three-pair development CPU screen over 24 ordinary or staged closures is in
`build/bench/finish-program-20261014/staging-pairs.{ts,json}`. Baseline
executable SHA-256 is
`afabd629b104af87cf45343597c54e2d332e1199d603188d0ed7a2236e92771c`; candidate is
`f1ad66ef7b6a9d048c9a331c40a7aebf62f54146026c97d34a72ba490a5ebdc0`. Staged
fresh/body-edit/literal-edit/revert median CPU ratios are
0.959/0.966/1.045/1.059. Ordinary retained phases are 0.985/0.987/1.009. These
mixed small differences establish no speedup. Both sides emit their exact fresh
Wasm and execute the expected result. Both also report 241 work steps for the
retained literal edit versus 265 fresh, while reusing one named backend body;
constant-receipt activity is zero. That existing accounting difference is
retained explicitly and this screen does not assert fresh/retained work
equality.

## Immutable producer data, 14 October 2026

Named future helpers can read immutable data owned by their producer. The proof
reconstructs the referenced global body, formal variables and selected type,
then checks its expression under that exact owner. Alias chains and pure scalar
or aggregate initialization share the existing depth/work budget. Runtime
globals, foreign owners and cyclic definitions still reject.

Seven focused named-body laws pass, including producer release, artifact
roundtrip, complete allocation failure and explicit runtime/foreign/cycle
mutants. The three changed imported-helper guest groups pass in 0.425 s; the
file now contains thirteen groups. Data edits, failed helper revisions, recovery
and restart agree with fresh bytes and 32 source steps in both guest modes.
Unchanged and recovered output reuse reports zero work. Affected-file lint
checks 226 of 418 files with zero findings, and Deno type checking passes. The
exact three-file follow-on is pinned in
`build/bench/finish-program-20261014/staging-producer-data-source/`; logs use
the `staging-global-data-*` prefix. Full combined qualification remains pending.

## Public nominal field descriptors, 14 October 2026

`@descriptor.fields` exposes the fields shared by all constructors of a public
nominal type. Source checking instantiates each constructor. Portable Core
independently matches each constructor result to the described nominal type,
checks its declared variables, and reconstructs every published field type. The
evaluator projects this checked recipe under the current type arguments.
Private/opaque owners and fields available in only one variant remain hidden.

Four focused native laws pass, including producer release, dependency roundtrip,
complete allocation failure and forged field/private-owner/missing-binder
mutants. All fourteen staging guest groups pass. The new guest changes a public
field between U32 and F32, checks common variant fields, and compares fresh,
retained and restarted bytes/fuel through source and compiled imports in both
codegen tiers and sync/JSPI. A failed access to a variant-only field preserves
the accepted executable. Pinned affected-file lint checks 322 of 418 files with
zero findings, and Deno type checking passes.

The six-file delta and executable pin are in
`build/bench/finish-program-20261014/nominal-descriptor-source/`, patch SHA-256
`099b68b8a8bd3cb0499b49b9bba6fd9057bd7cf00c9401a4b68b896c3e03fb2d`. Logs use
`nominal-descriptors-*`; early fixture/optional-return compile failures are
preserved separately. Full combined qualification remains pending.

## Generated diagnostic origins, 15 October 2026

Generated failures retain a bounded trace of the producer quotation, the actual
selected generator call, splices and invocation. Sparse Code metadata survives
typed views, aggregate copies, archive capture and pool leases; it confers no
type, provider or executable authority. Corrupt value/unit/node records reject
before publication. Native allocation-failure/archive/pool checks and both-tier
source/checkpoint/restart failure and recovery guests pass. Root qualification
also preserves aggregate owner behavior, with zero findings across 240 selected
files. Exact source, compiler and logs are pinned in
`build/bench/complete-program-20261015/generated-origins/`.

Closed sealed package staging and qualified owning carriers preserve their
original cleanup token. Foreign-only inferred rows require the exact current
body certificate. Initial missing-certificate native failures are preserved in
`sealed-packages/`; the separately reviewed correction passes three native/OOM
laws in `package-foreign-rows/`. These focused results await the final combined
gate and do not qualify general staging.

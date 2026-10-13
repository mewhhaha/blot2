# 024 — Apply general body interface cutoff

## Status, dependencies, and originating requirements

- **Status:** In progress — partial milestones through `2689ad5`; no completion
  is claimed.
- **Dependencies:** [023](023-narrow-literal-edit-invalidation.md)
- **Originating requirements:** PLAN: Hill 6 / general body edits under 100 ms.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Recheck changed bodies individually and stop semantic propagation when their
interfaces remain unchanged.

## Starting point

[module_frontend_cutoff.zig](../zig-native/src/module_frontend_cutoff.zig) and
refinement receipts provide limited cutoffs. The unified queries distinguish
semantic dependencies from executable and staging reads.

## Implementation checklist

- [ ] Compare complete public body interfaces after individual rechecking,
      including residual predicates, effects, captures and identities.
- [x] Stop semantic propagation only on exact interface equality; rebuild
      executable consumers of changed bodies, selected evidence, captures or
      staged inputs.
- [x] Preserve failed-revision rollback and dependencies across imports,
      namespaces and serialized artifacts.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Edit bodies with unchanged types but changed values, effect traces, demand
  control flow or lifetime summaries; executable callers must update.
- Change signatures, predicates and captures and verify semantic propagation
  resumes; test imports, dependencies, restart and correction.
- Measure first/later general body edit CPU, reused regions and metadata with
  fresh/retained equality.

## Acceptance criteria

- [ ] Unchanged interfaces stop semantic propagation without hiding executable
      or staged changes.
- [x] The under-100-ms body-edit target is measured or remains an explicit
      unfinished performance gate.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `a686304a31d49fe18f9f252e654995de7f10a951` (partial compiler
  milestone; the task stays open).
- Implementation: refinement receipts rooted in an edited module are admitted
  per declaration (body roots by exact projection and identity, closure roots by
  the exact projection of the declaration that reaches them), so unchanged
  declarations and consumers that read only an unchanged interface keep their
  semantic inference; executable fragments still rebuild every transitive
  caller. Hygienic loop names are numbered per top-level declaration, so
  size-changing edits no longer change the namespace.
- Validation: Zig 0.17.0 before every build batch. `deno task test:compiler`
  passes the full LLVM native suite and 632 guest/client tests;
  `deno task
  lint:zig` reports zero findings across 310 files. Native, gate
  and process-level laws cover replay, interface cutoff, revoked closures,
  demand and effect-trace changes with executed results, failed edits and
  recovery. `cli_profile.test.ts` no longer flakes on temporary path lengths.
- Comparison: 21 alternating repetitions over seventeen workloads at load 40–49:
  ecs edits 0.84–0.85 × CPU with refinement hits 10 → 58 of 82, monads 0.85 ×; a
  size-changing lists edit now keeps its gate but is 1.13 × slower;
  size-changing ecs and syntax edits are unchanged. Steady geomeans 0.972 (edit)
  and 0.969 (revert). Baseline `5bfae5b` (sources of `fbe28c8`).
- Remaining work (why the task is open): the frontend still rechecks every body
  of an edited module rather than the changed bodies individually; Core node and
  type IDs are module-global, so edits that add nodes or types renumber later
  declarations or change the type catalog and disable the gate; the symbol table
  is ordered by first use, so a new identifier spelling disables the gate. The
  under-100-ms target stays an unfinished gate for task 084.
- Durable record: [body interface cutoff](../zig-native/BODY_CUTOFF.md),
  [distributions](../zig-native/qualification/body-cutoff.csv) and
  [pins](../zig-native/qualification/body-cutoff-pins.json).

### Qualified owned-body slice — 12 October 2026

`46bf8b9` adds immutable leases and conservative replay with complete
closed-row, nominal/field and evidence receipts. The full native/914-guest
compiler gate, eight unchanged budgets and 348-file zero analyzer pass. Admitted
deep-body edit CPU falls about 29–30%; population/retained-memory costs and
cheap-body regressions remain explicit. Shared-callee and qualification
followups were isolated at that milestone. General forms, relocation and the
under-100-ms target keep this task open. See
[combined qualification](../zig-native/FRONTEND_OWNERSHIP_QUALIFICATION.md).

### Qualified shared/portable/annotation slice — 12 October 2026

`2689ad5` adds bounded completed shared principals, original declared
qualification owners through source/compiled imports, independent body offers
after seed rebuild and complete applied-annotation/constructor recipe reads. The
joint full native/925-guest gate, eight unchanged budgets and 349-file zero
analyzer pass. Unsupported blocks/cases and other forms, producer-unit ordinal
relocation and the total edit target stay open. Pinned isolated costs remain
distinct from mixed merged release costs. See
[BODY_CUTOFF](../zig-native/BODY_CUTOFF.md) and
[the combined record](../zig-native/ROW_FUSION.md#integrated-qualification).

### Qualified guarded scopes and local principals —12 October 2026

`850793f` fixes a confirmed retained dotted-access wrong result by declining
incomplete access-path metadata. It also admits owned ordinary block/case/
constructor scopes, predecessors/joins and unqualified local principals with
exact covariance rows. The joint native/936-guest gate, eight unchanged budgets
and 350-file zero analyzer pass. Captured 93-unit work still elaborates 80
bodies; no total edit gain is claimed. Explicit-field receipts are separately
frozen; compact access paths, requirements, relocation and the total target
remain open. See [BODY_CUTOFF](../zig-native/BODY_CUTOFF.md) and
[merged qualification](../zig-native/NUMERIC_SIMD.md).

### Qualified explicit fields —12 October 2026

`4013b10` owns explicit field tags/spellings and nominal receipts, preserving
current physical slots and variant indices. The full native/961-guest gate,
eight unchanged budgets and 351-file zero analyzer pass. Dotted access paths
remain declined; the sparse field header adds 32 bytes and no field-specific
LLVM speedup is claimed. Requirements, relocation and the total edit target
remain open. Exact merged/isolated evidence is in
[BODY_CUTOFF](../zig-native/BODY_CUTOFF.md).

### Isolated compact dotted paths —13 October 2026

The next reviewable slice owns concrete dotted record/nominal paths with all
intermediate types, field spellings, nominal recipes and variant tags. It adds
16 bytes per body header and reconstructs current physical slots. Fifty focused
native laws, a separate fresh/retained path OOM sweep,17 executed-Wasm laws,
eight unchanged budgets and371-file zero analyzer pass. Five matched Safe/noLLVM
pairs reduce dotted128/512 edit CPU123.5→90 /477.5→350.5ms and elaborations
130.5/514.5→2.5; population costs rise9–12%. These are development measurements.
Root's combined full gate, LLVM/Fast and captured-project acceptance remain
pending. Methods, local requirements, imported annotation heads, producer
relocation and the general total edit target keep024 and dependent053 open.
Exact implementation/cost boundaries are in
[BODY_CUTOFF](../zig-native/BODY_CUTOFF.md).

### Isolated inferred local requirements —13 October 2026

Flat inferred associated/result-selection local principals now own their
requirements through the existing sparse graph and predicate owner. Complete
candidate reads precede current instantiation; unsupported/exhausted proofs
remain ordinary. Native fresh/replay OOM,21 executed-Wasm laws, eight unchanged
budgets and371-file zero analyzer pass. Matched bounded Safe/noLLVM local64/128
edit CPU98.125→79.375 /188.125→152.5ms and elaborations69.5/133.5→5.5;
population costs rise22–25%. Written/shared local origins, other residual kinds,
relocation, full-gate/release acceptance and the total edit target keep024
and053 open. See [BODY_CUTOFF](../zig-native/BODY_CUTOFF.md).

### Isolated declared local qualifications —13 October 2026

Written associated/result-selection and representation local principals now
relocate exact where origins before current instantiation. Source and compiled
producer authority routes use the enclosing original declaration and local
clause position; portable snapshots and sparse receipt headers stay unchanged.
Native fresh/retained/population OOM and exact bounded clause controls,23body
guest laws, eight unchanged budgets and371-file zero analyzer pass. Matched
Safe/noLLVM declared64/128 edit CPU94.375→81.875 /183.75→158.125ms; elaborations
69.5/133.5→5.5. Population rises37–44%. Shared local edges, other residual
kinds, producer ordinals, broader forms, release/full-gate acceptance and the
total edit target keep024/053 open. See
[BODY_CUTOFF](../zig-native/BODY_CUTOFF.md).

### Isolated producer ordinal relocation —13 October 2026

Borrowed body offers now resolve by canonical filename. Owned nominal reads and
imported/associated/qualified principal receipts bind exact original module
origins and declaration names, while replay reconstructs current unit/binding
execution targets. Source and compiled insert/delete/renumber, equal-interface
retarget revocation, owning payloads, retained revision/allocation failures,
24body guest laws, eight budgets and371-file zero analyzer pass. Matched
Safe/noLLVM producer64/128 CPU172.5→156.875 /341.875→312.5ms and elaborations
66/130→2; population rises11%. Admitted producer ordinal relocation is covered;
shared locals, imported annotation heads, broader forms, other residual kinds,
full-gate/release acceptance and the total edit target keep024/053 open. See
[BODY_CUTOFF](../zig-native/BODY_CUTOFF.md).

### Isolated imported annotation heads and recipe proofs —13 October 2026

Capture/replay now use the checker's exact current nominal-name lookup while it
is alive. Sparse reads own original imported names and complete recipes through
source/compiled direct imports, aliases and namespaces; no new persistent name
table or receipt/archive header is added. A fixed body-local recipe memo retains
exact depth and proof-budget guards and resets across checker mutations.
59focused native/OOM laws,25body guests, eight budgets and371-file zero analyzer
pass. Matched Safe/noLLVM head64/128 CPU115.625→108.125 /223.75→208.125ms and
elaborations66/130→2; population rises15–17%. The rejected un-memoized
regression is preserved. Shared local requirements, other residuals, broader
forms, full-gate/release acceptance and the total edit target keep024/053 open.
See [BODY_CUTOFF](../zig-native/BODY_CUTOFF.md).

### Isolated shared local requirements —13 October 2026

Local principals now own completed shared callee edges through binding receipts
and restore their current targets before instantiation. Replay preserves the
local generalization boundary, avoiding duplicate enclosing requirements.
60native/OOM laws,26body guests, eight budgets and371-file zero analyzer pass.
Matched Safe/noLLVM local64/128 CPU120→89.375 /231.875→172.5ms and elaborations
70.5/134.5→6.5; population rises9–10%, steady RSS944/720KiB. Five additional
plain pairs are equal after a noisy initial control. Other residual/effect/
control forms, combined release acceptance and the total edit target keep024
and053 open. See [BODY_CUTOFF](../zig-native/BODY_CUTOFF.md).

### Isolated written Foreign arrows —13 October 2026

Explicit Foreign function-arrow syntax now uses the existing complete owned row
proof, including closed empty rows and symbolic written tails. Exact syntax
bounds and the sealed label identity require no schema growth.62 body native
laws,27 executed body guests,8 unchanged budgets and371-file zero analyzer pass
in isolation. Source/compiled callbacks preserve changed traces, reject a closed
pure annotation and recover. CPU5 Safe/noLLVM64/128 retained CPU falls 70→63.125
/136.875→120ms; population rises33%/25% and retained RSS604/1792KiB. Root's
combined release qualification remains separate. User-operation and
field/receiver/update residuals, other control forms and total edit performance
keep024/053 open. See[BODY_CUTOFF](../zig-native/BODY_CUTOFF.md).

### Isolated ordinary array selectors —13 October 2026

Array indexing is admitted through the existing owned expression facts, without
metadata/schema growth.63 native body laws,28 executed body guests,8 unchanged
budgets and371-file zero analyzer pass in isolation. Generic scalar/F32/owning
selectors cover source/compiled edits, selector diagnostics/recovery and every
capture/replay allocation failure. Safe/noLLVM64/128 retained CPU falls
64.375→56.25 /122.5→106.875ms; population rises17%/30%, retained RSS96/1224KiB.
An initial plain128 slowdown did not repeat across five further pairs. Root's
combined release gate remains separate; general residuals, mutation/control
forms and total edit performance keep024/053 open. See
[BODY_CUTOFF](../zig-native/BODY_CUTOFF.md).

### Isolated generic explicit fields —13 October 2026

Implicit field requirements now own exact variable-receiver templates and
complete member-catalog reads through the existing global/local principal graph.
Concrete physical paths retain complete variant checks; no header/schema grows.
65 body native laws,29 body guests,8 unchanged budgets and371-file zero analyzer
pass in isolation, including global/local capture/replay OOM, source/compiled
owning payloads, method value/effect edits and rejected-field recovery.
Safe/noLLVM64/128 retained CPU79.375→63.125 /151.875→119.375ms; population rises
14–15%, retained RSS1096/644KiB, plain controls remain near parity. Root's
combined release gate remains separate. Generic dotted/declared/projected
fields, other residual/control forms and total edit performance keep024/053
open. See [BODY_CUTOFF](../zig-native/BODY_CUTOFF.md).

### Isolated generic dotted templates —13 October 2026

Unqualified parameter/local dotted roots now own direct field requirements and
zero-tag variable steps through existing path receipts and complete member
reads. Concrete/method-path guards remain.19 focused dotted laws cover
global/local fresh/replay/population OOM and candidate revocation;29 body guests
plus8 budgets and371-file zero analyzer pass, with both source/compiled field
syntaxes. Safe/noLLVM64/128 retained CPU79.375→62.5 /153.75→120ms, population
rises14%/7%, retained RSS252/88KiB and plain controls stay at parity. Root owns
the combined release gate. Qualified/projected/declared fields, other
residual/control forms and total edit acceptance keep024/053 open. See
[BODY_CUTOFF](../zig-native/BODY_CUTOFF.md).

### Isolated compatible pure forms —13 October 2026

One bundle adds if-let, scalar negation, value patterns, product projection and
pure Array/List operations through existing facts/closures/joins. No schema
grows.68 native body laws qualify through65 initial passes and focused reruns of
three updated work counters (Array.concat now reuses);30 body guests,8 budgets
and371-file zero analyzer pass. Source/compiled callback/control/owning/variant/
value-pattern/failed-edit and population/replay OOM laws pass. Safe/noLLVM64/128
if-let retained CPU70.625→63.75 /135→120ms; collection67.5→59.375 /
131.25→114.375ms. Population costs rise17–36%; plain controls stay near parity.
Root owns combined release qualification. A bounded owned source-Core fragment
is the next architectural experiment; whole-module copying is rejected. The
remaining proof/control/effect/evidence classes and total edit target
keep024/053 open. See [BODY_CUTOFF](../zig-native/BODY_CUTOFF.md).

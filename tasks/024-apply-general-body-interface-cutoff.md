# 024 — Apply general body interface cutoff

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified on 19 October 2026 against the fixed
  acceptance scope; see the current completion record below.
- **19 October 2026:** CT26 (`c622b99`) stopped interface comparison from
  reading `obligation_spans`. A one-byte body edit no longer rechecks the 13
  importers of `robots.blot`: the gdev body edit went 1,616 → 1,228 ms. Still
  open: the body check cache admits none of `robots.blot`'s 107 bodies. See CT26
  in
  [COMPILE_HILLS.md](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/COMPILE_HILLS.md).
- **Dependencies:** [023](023-narrow-literal-edit-invalidation.md)
- **Originating requirements:** PLAN: Hill 6 / general body edits under 100 ms.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Recheck changed bodies individually and stop semantic propagation when their
interfaces remain unchanged.

## Starting point

[module_frontend_cutoff.zig](../zig-native/src/reuse/module_frontend_cutoff.zig)
and refinement receipts provide limited cutoffs. The unified queries distinguish
semantic dependencies from executable and staging reads.

## Implementation checklist

- [x] Compare complete public body interfaces after individual rechecking,
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
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Edit bodies with unchanged types but changed values, effect traces, demand
  control flow or lifetime summaries; executable callers must update.
- Change signatures, predicates and captures and verify semantic propagation
  resumes; test imports, dependencies, restart and correction.
- Measure first/later general body edit CPU, reused regions and metadata with
  fresh/retained equality.

## Acceptance criteria

- [x] Unchanged interfaces stop semantic propagation without hiding executable
      or staged changes.
- [x] The under-100-ms body-edit target is measured or remains an explicit
      unfinished performance gate (owned by task
      [102](102-reach-the-body-edit-target.md) since 15 October 2026).
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Closed acceptance — owner decision, 17 October 2026

The owner closed this task's scope to the fixed rows below. Rows 1–10 are the
body forms and edit classes the task's evidence already covers; row 11 is the
one concrete form class the evidence still names as missing. The checklist and
acceptance criteria above are read against these rows. A body outside them keeps
ordinary checking: semantic propagation does not stop there, which is always
correct, and the form is a recorded limitation rather than required work here.

1. Per-declaration refinement receipt roots and closure roots in edited modules;
   loop names that stay stable under size-changing edits
   ([receipt roots](../zig-native/BODY_CUTOFF.md#receipt-roots-in-edited-modules)).
2. Owned checked facts for scalar literals, U32/F32 intrinsics, applications,
   typed lambdas, conditionals, products and collection literals; generic
   nominal/structural and selected/residual evidence; closed-row certificates;
   earlier inserted AST/type nodes and new spellings
   ([owned body facts](../zig-native/BODY_CUTOFF.md#owned-frontend-body-facts-task-024-first-slice)).
3. Shared principal edges, source-declared and portable imported qualifications,
   seed-rebuild body offers, applied-annotation and constructor recipe reads
   ([shared edges](../zig-native/BODY_CUTOFF.md#shared-principal-edges-task-024-follow-up)).
4. Blocks, lets, returns, scalar rebinding, joins, case pattern rows,
   constructor patterns and unqualified local principals, with the access-path
   safety guard
   ([scopes](../zig-native/BODY_CUTOFF.md#ordinary-scopes-and-constructor-patterns)).
5. Explicit fields, concrete dotted paths, generic explicit fields,
   variable-root generic dotted templates, ordinary array selectors, field and
   indexed updates
   ([fields](../zig-native/BODY_CUTOFF.md#integrated-explicit-fields-at-4013b10),
   [updates](../zig-native/BODY_CUTOFF.md#field-and-indexed-update-receipts-15-october-2026)).
6. Inferred, declared and shared local requirements; producer ordinal
   relocation; imported annotation heads and recipe proofs; inert principal
   suffixes
   ([combined replay](../zig-native/BODY_CUTOFF.md#combined-replay-qualification-13-october-2026),
   [suffixes](../zig-native/BODY_CUTOFF.md#inert-principal-suffixes-15-october-2026)).
7. Written Foreign arrows; if-let, scalar negation, value patterns, product
   projection and pure Array/List operations; ordinary loops and `use`; demanded
   bodies
   ([loops](../zig-native/BODY_CUTOFF.md#ordinary-loop-and-use-receipts-15-october-2026),
   [demands](../zig-native/BODY_CUTOFF.md#ordinary-demanded-body-receipts-15-october-2026)).
8. Nongenerative user-effect callback rows; static calls to unparameterized
   effect families
   ([effect rows](../zig-native/BODY_CUTOFF.md#user-effect-callback-rows-15-october-2026),
   [operations](../zig-native/BODY_CUTOFF.md#static-operation-calls-15-october-2026)).
9. Mixed implementation modules, nominal/alias annotation recipes and
   selected-name callers within the 64-entry catalog and 4,096-step proof bounds
   ([implementations](../zig-native/BODY_CUTOFF.md#mixed-implementation-modules-14-october-2026),
   [callers](../zig-native/BODY_CUTOFF.md#current-selected-name-callers-14-october-2026)).
10. Executable consumers of changed bodies, selected evidence, captures and
    staged inputs rebuild; nested callable fragment owners; all-dirty dependency
    chains; failed-revision rollback; source/compiled/archive/checkpoint parity;
    complete allocation-failure sweeps
    ([nested fragments](../zig-native/BODY_CUTOFF.md#nested-callable-fragment-owners-15-october-2026),
    [chains](../zig-native/BODY_CUTOFF.md#chains-with-no-clean-dependency-15-october-2026)).
11. Implemented in the working tree: generic dotted paths with qualified roots,
    projected receivers and declared field requirements, with global/local and
    imported qualification origins. The extended row-5 matrix and the new native
    fault-sweep law pass; full LLVM qualification is pending. See the
    [closed acceptance map](../zig-native/BODY_CUTOFF.md#declared-fields-and-the-closed-acceptance-map-19-october-2026).

The task completes when row 11 is implemented, every native law and guest test
mapped to rows 1–11 passes in the full compiler gate (`deno task test:compiler`
and `deno task lint:zig`) on committed source, and the row-to-law mapping is
recorded in [BODY_CUTOFF.md](../zig-native/BODY_CUTOFF.md).

What moved where (nothing is dropped silently):

- **Under-100-ms body-edit target:** task
  [102](102-reach-the-body-edit-target.md), since 15 October 2026.
- **Structural blockers** named in the 11 October analysis (module-wide
  rechecking outside the admitted forms, module-global Core node and type IDs,
  first-use symbol order, and with them edits that shift shared principal
  slots): task 102's checklist, since 15 October 2026.
- **Body forms that still decline to ordinary checking**, as recorded in
  [BODY_CUTOFF.md](../zig-native/BODY_CUTOFF.md): generated iterator bodies,
  Request loops and resolver blocks; binary demand rewrites; scoped, generative,
  invocation and resource operation recipes; Scoped/State static calls and
  parameterized effect families; selection forms outside the bounded catalog,
  row-parameter catalogs and authority-bearing schemes; aliases hiding an
  associated projection; and any other residual, effect or control form the
  record lists as ordinary. They move to task 102, which admits one only when
  attribution on the 084 workload shows it blocking the body-edit target;
  otherwise each stays a recorded limitation. No new task is added: these forms
  matter only through the performance requirement 102 already owns.
- **Private-edit cutoff and wrapper erasure for module abstraction:** task
  [053](053-qualify-module-cutoffs-and-wrapper-erasure.md)'s own fixed rows.

## Completion evidence

- Current local milestone: `e29dd0d2c6faa2ad16a39e4a06ef254cede3ff2c`; compiler
  and exact source/log hashes are recorded by the
  [cloud qualification](../zig-native/CLOUD_QUALIFICATION.md).
- Validation: the forced LLVM gate executes all 2,470 native laws without skips,
  failures, leaks or logged errors; 1,556 guest/client checks and 37 harness
  checks pass. CI lint covers 507 source files plus the fixture module with zero
  findings. Strict fresh/retained/restart/shared Wasm parity and the seven-pair
  CPU regression guard pass.
- Acceptance: All eleven fixed body-cutoff rows pass, including declared field
  principals and forwarded qualified roots.
- Remaining limits: The under-100-ms body target and attribution-gated ordinary
  forms remain with task 102; no general gdev body-admission gain is claimed.

### Earlier implementation evidence

The checkpoints below retain their original dates and measurements. Statements
that qualification or a commit was pending refer to those earlier checkpoints.

- Current state: rows 1–10 are in committed source (the continuation landed in
  `23a934f`; the `05401a9` gate passes 2,355 native laws and 1,501 guest tests
  with zero analyzer findings). Row 11 and the row-to-law mapping are open.
- First milestone `a686304`: per-declaration receipt roots and stable loop
  names. Full LLVM native suite, 632 guest/client tests and 310 analyzer files
  at zero. Twenty-one alternating repetitions over seventeen workloads against
  `5bfae5b` (sources of `fbe28c8`): ecs edits 0.84–0.85 × CPU with refinement
  hits 10 → 58 of 82, monads 0.85 ×, a size-changing lists edit 1.13 × slower;
  steady geomeans 0.972 (edit) and 0.969 (revert). See
  [distributions](../zig-native/qualification/body-cutoff.csv) and
  [pins](../zig-native/qualification/body-cutoff-pins.json).
- Later milestones, each with a passing full gate: `46bf8b9` owned body facts
  (914 guests; admitted deep-body edit CPU about 25–30% lower); `2689ad5`
  shared, portable and annotation reads (925 guests); `850793f` scopes, local
  principals and the dotted-access wrong-result fix (936 guests); `4013b10`
  explicit fields (961 guests); `ae001bb` the 13 October field, local
  requirement, relocation and pure-form recipes (1,061 guests; retained
  synthetic CPU about 22–29% lower, population 15–39% higher). The 14–15 October
  implementation, loop, update, demand, effect-row, nested-fragment, all-dirty
  chain, inert-suffix and static-operation slices landed in `23a934f`.
- Measured costs: in 64/128-declaration development screens the admitted forms
  cut body elaborations per edit from about 66/130 to 2 and retained edit CPU by
  about 6–54%, while population CPU rises about 7–45% and retained memory
  usually grows. These are Safe/noLLVM screens; no total edit gain on the
  captured 93-unit project is claimed.
- Remaining: full LLVM qualification, the paired compiler comparison and a local
  milestone commit. Row 11 and its durable law map are implemented and focused
  checks pass. Limitations and moved scope remain explicit above.
- Durable record: [body interface cutoff](../zig-native/BODY_CUTOFF.md) (every
  slice, its laws, pins and costs),
  [frontend ownership](../zig-native/FRONTEND_OWNERSHIP_QUALIFICATION.md) and
  [merged qualification](../zig-native/CONTINUATION_QUALIFICATION.md).

# Continue here

The owner wants the entire program in [tasks/README.md](tasks/README.md)
finished. Continue past individual milestones. **Nothing is pushed.** Keep old
artifacts and private working trees; artifact deletion/pushing still require
their separate owner decisions.

## Qualified main

Latest compiler implementation: `6a57437`. Latest design: `07cbc62` (057).
045/046 are complete: ordinary rolling fold/monoid/group windows and opaque
persistent AVL summary build/get/query/set/concat. 057's scoped-effect design is
complete; 058–059 are not implemented. Earlier completed milestones remain in
the task index and durable records.

- Qualified tree: `885c7d8a8461d404990a309d89d095fceb24e85f`; compiler source:
  `b9d9208f0938ab2111a913328a8b0992792623c3`. LLVM/Fast SHA:
  `904b1ac1558ae3d5c9b1c11744f6cf45a096297753b4b8e572fc4bb99935adb2`. Immutable
  binary/pins: `build/bench/joint-047-086-qualified/`.
- Full native/OOM suite,973 guest/client tests, eight unchanged budgets and
  355-file zero-finding analyzer pass with Zig0.17.0. The final test-only wire
  counter correction reuses the preceding successful native cache.
- Owning-field locals remove4097 Array cursor objects and4096 generic pipeline
  objects. Three merged all-width F32 cursor comparisons pass; U32 tails and
  other adapters remain open. Validated primitive constant and ready member
  receipts qualify modest measured edits; dominant captured constants remain
  ordinary. The captured project regresses about5% from double fallback
  assembly. See
  [merged qualification](zig-native/ITERATOR_CONSTANTS_QUALIFICATION.md).
- Earlier rolling/summary, body-cutoff and tracing milestones remain qualified.
  Scalar state and direct named reference environments are recorded in
  [ITERATOR_STATE](zig-native/ITERATOR_STATE.md) and
  [TRACING_REPLACEMENT](zig-native/TRACING_REPLACEMENT.md).

## Active work

Continue past partial checkpoints. Combined047/086 is qualified at6a57437. 053
depends on024. Preserve rejected pins/logs and keep main source frozen through
each gate.

- **047 next:** isolated `/var/tmp/blot2-next-047-058` contains reviewed table
  projections, static058 and early conservative source-conflict cost admission.
  Unqualified integration basis `ec6a2ae41c92c9025ced4fada28e502ad354756c`, tree
  `470f8402ad4f1b0af68ef0b2b60a06778ae6e826`, parent6a57437. Focused native, 21
  merged guests and355-file zero analyzer pass. One matched Safe captured pair
  preserves bytes/fuel and roughly halves assembly; no release CPU claim.
  Projection pins: `build/bench/iterators-047/table-projection/`; isolatedLLVM
  c31847b2 removes4096 more pipeline boxes, with runtime ratios
  1.0117/0.9728/0.9208 and86207 extra requested compiler bytes.
- **047 U32:** `/root/resolved_body_028` freezes a separate four-local
  word-position delta after17 native/Core/replay/OOM,18 guest groups,8 budgets
  and352 analyzer/zero. Quiet matched Fast/noLLVM U32 width7/16 ratios are
  record0.8966/0.9585 and tuple0.9343/0.9928; F32 controls improve slightly.
  LLVM qualification is starting onCPU4, runtimeCPU7. The boxed U32 tail remains
  open. A later leaf-directory proposal is separate and unimplemented;
  duplicated/irregular leaf positions require more than pointer equality.
- **056:** `/root/associated_members_055` preserves immutable235 in
  `/var/tmp/blot2-implementations-056-qualified`, base46bf8b9. Additional
  measured DAG gaps in exact comparison, raw unification and optional source
  admission were found and fixed separately. Closed64 proof controls now have
  bounded CPU/work and zero teardown. Final74-law/OOM sweep, guests and analyzer
  precede a NEW isolated port onto explicit `ec6a2ae41` basis. Preserve
  static058 argument closure/chronology, dotted access guard, optimizerv15
  features and all seven exact catalog comparisons in the constant-only gate.
  Root owns the combined full gate.
- **058:** static symbolic rows are included only in that next basis. Frozen
  original slice/evidence: `/home/jacobt/src/blot2-task058`, ignored
  `build/bench/scoped-static-058/`. Seven Safe/noLLVM public controls show
  1.5–2.4% CPU overhead, unchanged allocation; closed State and source/compiled/
  retained/checkpoint controls pass. The agent hit model capacity after saving
  evidence. No work was lost. Fresh identities, subtraction/routing and
  activation-owned revocation remain unimplemented;058/059 remain open.
- **086:** approved primitive constant and ready member checkpoint is qualified
  at6a57437. Dominant captured constants remain ordinary, with zero dedicated
  bookkeeping and no project-level payoff. Growth/enclosing judgments, escaping
  typed views, relocation/serialized-data breadth and portable member authority
  remain open. Preserve `build/bench/constant-receipts/` slices.
- **035:** scalar/direct environments are qualified; physical tracing removal,
  whole-module coverage and historical CPU acceptance remain open.
- **024/093:**80 edited-module bodies in the93-unit capture still elaborate.
  Dotted paths, local requirements, producer relocation and100ms target remain
  open.093 ordinary work is authorized. Current input differs from historical
  400ms evidence.

Agents do not edit main or run duplicate full gates. Root reviews frozen inputs
and runs one combined gate per commit-ready batch. Keep isolated, rejected and
merged costs separate.

## Build and validation

- Check `zig version` before each build batch; use Zig 0.17.0.
- Incremental:`deno task build:compiler:dev` uses Safe/noLLVM;
  release:`deno task build:compiler` uses LLVM/Fast. See
  [iteration costs](zig-native/ITERATION_COST.md).
- Focused native in `zig-native/`:
  `zig build test -Doptimize=safe -Dllvm=false
  -Dtest-filter="name"`. Use LLVM
  for expensive OOM sweeps.
- Before compiler commits:`deno task test:compiler` and
  `ZIG_ANALYZER=build/tools/zig-analyzer/zig-out/bin/zig-analyzer deno task lint:zig`.
  Zero findings required. Use `deno fmt --no-config` for zig-native files.
- Stage intended work only; separate implementation/record commits. Record exact
  binary/source/input pins, failures, costs and unfinished gates.
- Fast/noLLVM allocation screens use production allocation; Debug cannot prove
  release deltas. Accepted costs still use LLVM/Fast.
- Full native runs are expensive: the prior 1353-law suite took 298 s
  (typed-path OOM82 s, partial-runtime OOM27 s, request-backend OOM19 s). Avoid
  repeated gates; preserve failure coverage if optimizing them. NoLLVM full
  execution was 16 m 47 s, so retain LLVM for the full suite.

## Packages and other sessions

bpm is complete at `2798ff9`: Git/local/transitive exports, caching, exact
locks, frozen installs, updates and clean-cache checks. The owner's choice is
**omitted/null prelude means no prelude**. No package is published. See
[packages](compiler/packages.md).

gdev/pen contain other sessions' uncommitted work. Read them; never edit or
commit their private source into blot 2. gdev links `../blot2`, so a root gate
repacks `generated/compiler/blotc.gz` and changes its compiler with main's
`std/`. Current captured asset roots are `src` and `devtools`. Private snapshots
stay ignored/read-only; peer messages are not owner approval.

The missing original boxed/prewalk binaries and old frozen gdev manifest were
waived on 11 October. Do not ask to restore legacy artifacts again. Qualify
current reproducible workloads; retain the reconstructed boxed reference and
all-width cursor requirement for 047. See
[LIST_TRAVERSAL](zig-native/LIST_TRAVERSAL.md).

Pending owner choices: unapplied `/var/tmp/blot2-names.patch` (always-on Wasm
names,+5% bytes) and tuple patterns in comprehension generators. Neither blocks
ordinary authorized work. 082 push/remote evidence and 083 artifact deletion
need explicit decisions;999 waits for every required task.

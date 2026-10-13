# Continue here

Finish the entire program in [tasks/README.md](tasks/README.md), continuing past
individual milestones. **Nothing is pushed.** Preserve private worktrees and old
artifacts; tasks 082/083 still require their distinct owner decisions.

## Qualified main

Compiler `10fab46` completes 056 and extends 024/047/058/086. The full gate
passes 1,624 native laws, 1,030 guest/client tests and 977 exhaustive
allocation-failure sweeps; analyzer zero across 373 files.
[Merged qualification](zig-native/CONTINUATION_QUALIFICATION.md) records exact
behavior, failures and final measurements.

- Frozen tree: `46b8d009c1cb51cf8cb195e5ddfc2a406ea4659a`; native source:
  `c9fe14fd7fa33d4572f337d47f3833106b5b65ba`.
- LLVM/Fast SHA-256:
  `25232004dd54b576e41c467693eba585ae7abb1543ce39a1d0ebeed541e30dd6`. Immutable
  binary/logs/pins: `build/bench/continuation-20261013/`.
- Pipeline objects 53,254→36,870, requested payload 409,648→294,960 bytes, guest
  CPU ratio 0.8308. All packed-width medians beat reconstructed boxed across
  three runs. Broader state allocation remains 047.
- Seven captured pairs regress about 12% fresh and 9% edit/revert against
  qualified `6a57437`; public programs add 4–6% CPU. No compiler speedup is
  claimed. Constant receipts/indexes still have zero activity in that capture.
- The unrelated `deno.lock` change belongs to existing work. Preserve it.

## Active work

Agents own isolated worktrees; root reviews immutable deltas and runs one
combined full gate per commit-ready batch. Main source stays frozen during each
gate. Preserve isolated, rejected and merged pins separately.

- **024:** `/tmp/blot2-task024-completion`. Inferred local requirements through
  `51a2f752` are merged. Next frozen declared-local checkpoint `ade73b431` adds
  written associated/result/type-representation clauses; patch and measurements
  are in its `build/bench/task024-declared-local/`. It has focused native/OOM,
  guest and analyzer evidence, but awaits merged release qualification. Producer
  unit/binding relocation is the next isolated delta. General body coverage and
  093's 100ms goal remain open; 053 depends on full 024.
- **047:** `/var/tmp/blot2-adapter-children-047`, based on accepted tagged
  constructor tree `52262dd`. Child aggregates and journal-owned carriers are
  under development. The accepted table projections, packed word positions, leaf
  directory, eager row-tail and tagged-state slices are in `10fab46`. Preserve
  the reconstructed boxed binary and all-width comparisons.
- **058/059:** `/var/tmp/blot2-generative-effects-058`. Through sixth checkpoint
  `2a697c0b` is merged. Seventh `2e494e8a` is frozen under
  `/var/tmp/blot2-generative-058-checkpoints/public-flow/flow.patch`; public
  binder identity/Unit invocation contracts await the next combined gate. Eighth
  generic dependent-identity work is still isolated. Keep root row-refresh and
  worklist repair separate in its base chain. Generic parameter transport,
  selected identity and complete escape graphs remain open.
- **086:** `/var/tmp/blot2-constant-continuation-20261013` starts from the exact
  merged source. Instrumentation is saved separately and restored from source;
  its existing development binary is still instrumented. Largest captured
  constant consumes 57,019/70,330 source steps; its first declined observation
  is collection growth, with 227 expression inference observations on an edit.
  Growth state, inference/query tapes, typed views, sparse graph relocation and
  portable data authority remain open. Do not admit compound graphs using the
  old dense-index prototype; its bookkeeping cost already failed qualification.
- **035:** scalar/direct environments are qualified. Physical tracing removal,
  whole-module coverage and CPU acceptance remain open. Three ownership guest
  batches keep 131,072 committed bytes; async-scalar CPU ratios vary
  1.2844/1.0963/1.0194, so they do not close performance qualification.
- **069/070:** 069's [erased proof design](zig-native/ERASED_PROOFS.md) is
  complete; 070 is ready. Implement the distinct proof kind, exact value
  operands, checked constructors, explicit public contracts and complete
  boundary validation. 071 then handles automatic branch facts/check
  elimination. Neither is implemented.

## Validation and iteration

Use Zig 0.17.0; check `zig version` before every build batch. Development:
`deno task build:compiler:dev`; release: `deno task build:compiler`.
`deno task test:compiler:dev --native-filter="name"` runs focused work.
`--native-suite=syntax`, `types` or `runtime` selects a smaller native root;
`--native-llvm` accelerates expensive fault sweeps. Guest positionals must be
actual `.test.ts` files. Fixtures now live beside the selected compiler.

Before compiler commits, run the full `deno task test:compiler` and
`deno task lint:zig` (zero findings). The pinned analyzer is available at
`/home/jacobt/.cache/blot-tools/zig-analyzer-0.17.0-1-x86_64-linux/bin/zig-analyzer`.
Use `deno fmt --no-config` for Zig-directory Markdown. Stage intended files
only; separate implementation and qualification-record commits.

The latest gate took 839.91s: release build 199.90s, native compile 277.96s,
native run 331.97s and guests 18.17s. Focused preflight before the gate catches
integration failures cheaply. Full native execution stays LLVM; noLLVM is useful
for compiling changed focused code.
[Iteration costs](zig-native/ITERATION_COST.md) retain earlier measured
improvements. CI's pinned analyzer installer was checked locally; no remote
workflow has been triggered.

## Packages, artifacts and other sessions

bpm is complete at `2798ff9`: Git/local/transitive exports, caching, locks,
frozen installs and updates. Omitted/null prelude means no prelude. No package
is published; see [packages](compiler/packages.md).

gdev/pen contain other sessions' changes; never edit or commit their private
source into blot. gdev links `../blot2`; changing main's ignored compiler bundle
changes its compiler alongside main's `std/`. Current captured asset roots are
`src` and `devtools`. Private snapshots remain ignored/read-only.

The missing historical boxed/prewalk binaries and old frozen gdev manifest were
waived on 11 October. Qualify current reproducible workloads; retain the
reconstructed boxed reference and all-width cursor requirement. Old measurements
on different source snapshots do not establish a current speedup.

Pending owner choices: `/var/tmp/blot2-names.patch` (always-on Wasm names, about
5% more bytes), tuple patterns in comprehension generators, task 082 push/remote
evidence and task 083 deletion. Ordinary authorized work continues
independently. Task 999 waits for every required task.

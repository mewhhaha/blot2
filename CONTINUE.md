# Continue here

Finish the entire program in [tasks/README.md](tasks/README.md), continuing past
individual milestones. **Nothing is pushed.** Preserve private worktrees and old
artifacts; tasks 082/083 still require their distinct owner decisions.

## Qualified main

Compiler `b145c5e` extends 024/047/058/086; `10fab46` completed 056. The latest
full gate passes 1,651 native laws, 1,043 guest/client tests and 1,002
exhaustive allocation-failure sweeps; analyzer zero across 374 files.
[Merged qualification](zig-native/CONTINUATION_QUALIFICATION.md) records exact
behavior, failures and final measurements.

- Frozen tree: `a576172aa23e937ee5abdad6326a056adc880203`; native source:
  `dda64a9fad2855179f5846d8774477b217398ad3`.
- LLVM/Fast SHA-256:
  `b47b376058beecb41c22703a8e360985259fe79d878a7e3545e97e3a1d73faab`. Immutable
  binary/logs/pins: `build/bench/continuation-20261013/`.
- Pipeline objects 36,870→0, requested payload 294,960→0 bytes, guest CPU ratio
  0.0121 against `10fab46`. All 62 packed-width outputs retain exact qualified
  Wasm. Strict/window and callback allocations remain 047.
- Seven captured pairs regress about 5% edit/revert against `10fab46`; public
  programs add 0–3.6% CPU. Backend assembly adds about 47 ms. Both binaries
  optimize all 2,864 functions with zero retained reuse; investigation is
  active. Constant receipts/indexes still have zero activity in that capture.
- Shared graph scratch improves the large-snapshot primitive constant workload
  about 16%; small-snapshot controls remain near parity.
- The unrelated `deno.lock` change belongs to existing work. Preserve it.

## Active work

Agents own isolated worktrees; root reviews immutable deltas and runs one
combined full gate per commit-ready batch. Main source stays frozen during each
gate. Preserve isolated, rejected and merged pins separately.

- **024:** `/tmp/blot2-task024-completion`. Through imported-head checkpoint
  `cc6e5e4e` is merged. Shared-local, Foreign-arrow and index deltas through
  `c3cbfce9` are in the following integration tree. Generic explicit-field
  checkpoint `35dab36f` is frozen separately with focused/OOM/guest evidence.
  General body coverage and 093's 100ms goal remain open; 053 depends on full
  024. Its inactive cache moved intact to
  `/var/tmp/blot2-task024-cache-preserved/zig-cache`; the original path is a
  symlink. Use `TMPDIR=/var/tmp` to avoid filling the 16 GiB `/tmp` tmpfs.
- **047:** Child-state checkpoint `f67f836c` from
  `/var/tmp/blot2-adapter-children-047` is merged. Private callback elimination
  is being measured in `/var/tmp/blot2-adapter-cost-047`; it stays separate
  until frozen and reviewed. Then investigate zero optimized-body reuse on the
  actual captured workflow. Preserve boxed references and all-width comparisons.
- **058/059:** `/var/tmp/blot2-generative-effects-058`. Through tenth checkpoint
  `3bcadb54` is merged, including public flow, parameter transport, curried
  callbacks and trusted local storage. Eleventh complete-arrow patch is frozen
  under `/var/tmp/blot2-generative-058-checkpoints/complete-arrow/arrow.patch`
  and integrated into following. Multiple inputs, selected identity and hidden
  capture/store contracts remain open. Keep later slices separate.
- **086:** Sparse graph inspection and request-shared scratch are merged.
  `/var/tmp/blot2-constant-growth-20261013` freezes primitive collection growth
  at `d624723e`; following includes its delta. Focused/OOM/guest tests and
  analyzer pass. Release retained ratios at 32/512/2048 elements are
  0.9766/0.7210/0.4650; 4096 hits the existing typed-view limit and costs about
  3% more. Captured edits remain near parity with no constant activity. Largest
  captured constant still consumes 57,019/70,330 source steps and 227 inference
  observations; compound graphs, query/view publication and portable authority
  remain open.
- **035:** scalar/direct environments are qualified. Physical tracing removal,
  whole-module coverage and CPU acceptance remain open. Three ownership guest
  batches keep 131,072 committed bytes; async-scalar CPU ratios vary
  1.2844/1.0963/1.0194, so they do not close performance qualification.
- **069/070:** 069's [erased proof design](zig-native/ERASED_PROOFS.md) is
  complete; 070 is ready. Implement the distinct proof kind, exact value
  operands, checked constructors, explicit public contracts and complete
  boundary validation. 071 then handles automatic branch facts/check
  elimination. Neither is implemented.

The next integration is `/var/tmp/blot2-continuation-following-20261013`, based
on `7cb2b3e` plus all of the qualified `b145c5e` patch. It includes both stale
fixture repairs, primitive growth, the three additional 024 slices and complete
scoped arrows. Combined focused guests/budgets, frontend and analyzer pass; its
full gate has not run. Close scope after the private callback delta and qualify
the frozen combined release. Do not reapply its whole base onto main; take the
difference from qualified tree `a576172a`.

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

The latest successful gate took 682.24s: release reuse 0.05s, native compile
280.89s, native run 370.03s and guests 18.93s. The preceding failed gate built
the exact release in 212.88s; two test-only repairs preserved that binary.
Focused preflight catches integration failures cheaply. Full native execution
stays LLVM; noLLVM is useful for compiling changed focused code.
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

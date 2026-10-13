# Continue here

Finish the entire program in [tasks/README.md](tasks/README.md), continuing past
individual milestones. **Nothing is pushed.** Preserve private worktrees and old
artifacts; tasks 082/083 still require their distinct owner decisions.

## Qualified main

Compiler `38e822d` extends 024/047/058/086; `10fab46` completed 056. The latest
full gate passes 1,664 native laws, 1,053 guest/client tests and 1,011 complete
allocation-failure sweeps plus two expected-error sweep laws; analyzer zero
across 374 files.
[Merged qualification](zig-native/CONTINUATION_QUALIFICATION.md) records exact
behavior, failures and final measurements.

- Frozen tree: `52b6c36abad5f25f589fb0a6ba0e17d0e681f090`; native source:
  `101404d4442bfa27373199d1a7885ad6cffaaa62`.
- LLVM/Fast SHA-256:
  `bbf4fb62168a056aa3b55b439c2a509cd0781e2d691f000a809e09ec1bcbd9a3`. Immutable
  binary/logs/pins: `build/bench/continuation-20261013/`.
- Enumerate/zip objects 8,192/4,096→0 against `b145c5e`; the pipeline retains
  zero objects. All 62 packed-width outputs retain exact qualified Wasm. Strict
  zip still uses 45,062 objects and windows 81,894 at 4,096 rows.
- Seven captured pairs remain near parity against `b145c5e`; all 13 public
  outputs and allocation counts match. Earlier compiler regressions remain. A
  diagnostic found that repeated whole-graph matching exhausts its work budget
  before it can reuse 2,863 unchanged bodies. The bounded worklist repair is
  isolated and under qualification.
- Growing primitive constants improve retained CPU about 28% at 512 elements and
  53% at 2,048, with 3–6% population cost. At 4,096 elements the existing
  typed-view limit declines reuse and costs about 4% more. Captured constants
  still have zero receipt/index activity.
- The unrelated `deno.lock` change belongs to existing work. Preserve it.

## Active work

Agents own isolated worktrees; root reviews immutable deltas and runs one
combined full gate per commit-ready batch. Main source stays frozen during each
gate. Preserve isolated, rejected and merged pins separately.

- **024:** `/tmp/blot2-task024-completion`. Shared-local, Foreign-arrow and
  index deltas through `c3cbfce9` are merged. Generic explicit/dotted-field
  checkpoints `35dab36f`/`f72b7d91` are frozen separately with focused/OOM/guest
  evidence. Investigate one bounded owned source-Core fragment per declaration
  to replace the growing syntax whitelist. General body coverage and 093's 100ms
  goal remain open; 053 depends on full 024. Its inactive cache moved intact to
  `/var/tmp/blot2-task024-cache-preserved/zig-cache`; the original path is a
  symlink. Use `TMPDIR=/var/tmp` to avoid filling the 16 GiB `/tmp` tmpfs.
- **047:** Private child state and scalar callback checkpoint `07924a7e` are
  merged. `/var/tmp/blot2-retained-matcher-047` owns the bounded optimizer
  matching repair on exact tree `52b6c36a`. Its prototype reuses 2,862 of 2,864
  bodies on the actual captured edit; release qualification is pending. Preserve
  boxed references and all-width comparisons.
- **058/059:** `/var/tmp/blot2-generative-effects-058`. Through the eleventh
  complete-arrow checkpoint is merged. The twelfth multiple-input member slice
  is frozen under
  `/var/tmp/blot2-generative-058-checkpoints/paired-capability/pair.patch`.
  General selected identity terms, invocation binders, capture/result/store
  footprints, opaque boundaries and lifetime contracts remain open. Keep later
  slices separate.
- **086:** Sparse graph inspection, shared scratch and primitive collection
  growth are merged. `/var/tmp/blot2-selected-inference-20261013` contains
  diagnostic-only instrumentation for repeated partial Array-member queries; do
  not merge its logging or use its Safe clocks as release evidence. Largest
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

`/var/tmp/blot2-continuation-following-20261013` is the frozen, fully qualified
source of `38e822d`, based on `59fcd6b`. Preserve it. The next integration
should start from current main and take only later isolated deltas, including
the 024 generic-field paths, 058 multiple-input work and the optimizer matching
repair.

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

The latest successful gate took 889.65s: release build 200.39s, native compile
280.54s, native run 375.67s and guests 20.56s. Focused preflight catches
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

# Continue here

Finish the entire program in [tasks/README.md](tasks/README.md), continuing past
individual milestones. **Nothing is pushed.** Preserve private worktrees and old
artifacts; tasks 082/083 still require their distinct owner decisions.

## Qualified main

Compiler `0d77afc` adds multi-input callback and record capability footprints,
and reduces window allocations. The latest full gate passes 1,701 native laws,
1,075 guest/client tests and 1,050 complete allocation-failure sweeps plus two
expected-error harness laws; analyzer zero across 375 files.
[Merged qualification](zig-native/CONTINUATION_QUALIFICATION.md) records exact
behavior, failed/regressed runs and final measurements. There are 67 complete, 7
in progress and 26 pending tasks: 33 remain open.

- Frozen tree `6ccad03d86cf095786689121cbc888a1cd54ebdb`; native source
  `971d1a215326ce2e86db54ada1f11ef892f9f7c6`.
- LLVM/Fast SHA-256:
  `b4fb67ca4eab5de4dfb923cab4b0c24c759b484f5817453fe4d19af8e26793a8`. Main's
  ignored executable and compressed bundle match. Immutable evidence:
  `build/bench/continuation-20261013/invocation-qualified-pins.json`.
- The preceding `ae001bb` batch's seven captured pairs against `38e822d`: fresh
  2225.518→1950.672 ms; edit 1247.822→906.212 ms; revert 1147.918→813.715 ms.
  Paired ratios 0.8767/0.7266/0.7084; exact Wasm and source fuel. Public CPU
  stays near parity, and all 62 packed-width outputs remain exact. Final task
  084 targets remain unmet.
- Latest seven captured pairs against `5378347` show paired fresh/edit/revert
  CPU ratios 1.0049/1.0074/1.0051. The feature adds a small measured cost.
  Thirteen public programs and all 62 packed-width outputs retain exact Wasm;
  public allocation and peak bytes are unchanged. Each side uses its own pinned
  standard library. Release handshake and independent fresh configure agree on
  identity. Never copy another worktree's Zig configure cache.
- Exact checked length bodies avoid 220 inference regions and element/capture
  interface reconstruction. The bounded optimizer worklist reuses 2,862/2,864
  bodies. A replay fix preserves monomorphic pattern-payload roots; strict
  catalog validation stays unchanged. The original uncorrected combined batch
  regressed revert and failed a stale lexical-capture guest assertion; it is
  retained separately and never qualified.
- Generic explicit/dotted fields, if-let and pure collection recipes improve
  synthetic edits about 22–29%, with 15–39% population cost. The multiple-input
  scoped member checkpoint is included. General body/effect coverage remains
  open.
- Enumerate/zip objects remain zero. Strict zip falls 45,062→0 objects and
  2.899→0.030 ms at 4,096 rows. Windows falls 81,894→77,800 objects and
  1,277,540→1,244,788 payload bytes; root stores increase. Root runtime ratio
  0.9933 is near parity. Remaining window state and traversal costs stay open.
  Growing primitive constants retain the earlier 28–53% retained CPU win at
  512–2,048 elements; captured constants still have zero receipt activity.
- Preserve the unrelated `deno.lock` change (SHA-256
  `9ca792a967d134b10168500f68a576a67008431574b7007e14978d22d7e4e781`).

## Active work

Agents own isolated worktrees. Root reviews immutable deltas and runs one
combined full gate per commit-ready batch. Preserve isolated, rejected and
merged pins separately; freeze source during qualification.

- **024:** `/var/tmp/blot2-task024-core-fragment-prototype` explores one bounded
  owned source-Core fragment per declaration. Its additive prototype removes
  most lowerings but is slower and is not mergeable; fix ordinary emission
  ordering and remove duplicated work before qualification. A tiny-body fixture
  also exposes an existing covariance-certificate replay difference when the
  minimum-body threshold is disabled. General coverage and 053 remain open.
  `/var/tmp/blot2-later-without-pairs-20261013` preserves the merged 17-line
  pattern-payload repair and controls. Original syntax checkpoints remain in
  `/tmp/blot2-task024-completion`. Its inactive cache is preserved in
  `/var/tmp/blot2-task024-cache-preserved/zig-cache` through a symlink.
- **047:** The retained optimizer worklist, structured control-frame exits and
  narrow completed-empty-producer rule are merged and qualified. Preserve frozen
  `/var/tmp/blot2-iterator-remainder-047` and
  `/var/tmp/blot2-iterator-windows-047`. Active
  `/var/tmp/blot2-iterator-window-fold-047` attributes the remaining 77,800
  window allocations. Replacing the diagnostic inner fold alone removes 28,658
  objects but increases payload bytes; that is not an accepted improvement.
- **058/059:** Selected identities, pure aggregate parameter footprints and
  multi-input Unit callback invocation are merged and qualified, including
  standalone footprint-domain suite registration. Source and compiled helpers
  preserve exact owners, row multiplicity and record fields. Active
  `/var/tmp/blot2-generative-effects-058` develops exact member-closure captures
  in a separate post-record checkpoint. General parameter/capture/result/store
  graphs, invocation binders, opaque/associated boundaries and generative public
  contracts remain open.
- **070:** `/var/tmp/blot2-erased-proofs-070`, staged base `d55ab1cd`, owns
  unmerged syntax, public recipes, proof kind and exact source body/call checks.
  Frozen tree `7cfa6e5d`, patch SHA-256
  `9448b407d7c4158ecd636804f113678b49cb7ff8ac973f5c8c6b44b2f6fabde8`:
  `build/bench/continuation-20261013/proof-call-foundation/`. Focused numeric
  laws 41/41, separate full syntax suite 41/41, all eight unchanged budgets and
  380 analyzer files zero. Constructors retain exact aliases, rebindings,
  ordered operands and false guards as owned source metadata. Direct explicit
  local proof calls match complete prior argument recipes; type-only function
  aliases cannot grant another contract. Repeated consistency checks share the
  body work budget. Core guard lowering is newer, isolated work. Runtime guard
  execution, compiled authority, proof results, erasure and full qualification
  remain open. Never bridge the proof kind through Unit. See
  [proof qualification](zig-native/NUMERIC_PROOF_QUALIFICATION.md); 071 waits
  for 070.
- **086:** Sparse inspection/shared scratch/primitive growth and shape-only
  length calls are merged. The largest captured constant still uses
  57,019/70,330 source steps; compound graphs, query/view publication and
  portable authority remain open. Preserve diagnostic-only
  `/var/tmp/blot2-selected-inference-20261013`; never merge its logging.
- **035:** Physical tracing removal, whole-module coverage and CPU acceptance
  remain open. Prior async-scalar batches retain 131,072 committed bytes and CPU
  ratios 1.2844/1.0963/1.0194; these do not close qualification.

`/var/tmp/blot2-continuation-selected-20261013` is the frozen qualified source
of `121eb59`, based on `ab4ab86`. Preserve it, the previous
`/var/tmp/blot2-continuation-later-20261013` and the older fully qualified
`/var/tmp/blot2-continuation-following-20261013`. The latest frozen source is
`/var/tmp/blot2-continuation-invocation-20261013`, based on `2992c80`. Start the
next integration from current main and apply only later isolated deltas.

## Validation and iteration

Use Zig 0.17.0; check `zig version` before every build batch. Set
`TMPDIR=/var/tmp` so compiler caches do not exhaust the 16 GiB `/tmp` tmpfs.
Development: `deno task build:compiler:dev`; release:
`deno task build:compiler`. Focused native development supports
`--native-filter` and `--native-suite`; `--native-llvm` accelerates expensive
fault sweeps. A dev invocation without filters or actual positional `.test.ts`
files runs only smoke tests.

Before compiler commits, run `deno task test:compiler` and zero-finding
`deno task lint:zig`. The pinned analyzer is
`/home/jacobt/.cache/blot-tools/zig-analyzer-0.17.0-1-x86_64-linux/bin/zig-analyzer`.
Use `deno fmt --no-config` for files under `zig-native/`. Stage intended files
only; separate implementation and qualification-record commits.

The latest gate took 911.55s: release build 203.27s, native compilation 280.31s,
native execution 392.46s and guests 21.50s. Focused preflight catches
integration failures cheaply. Preserve exhaustive OOM coverage. Full native
execution stays LLVM; noLLVM reduces focused rebuild cost.
[Iteration costs](zig-native/ITERATION_COST.md) retain earlier improvements.
CI's pinned analyzer installer was checked locally; no remote workflow has run.

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

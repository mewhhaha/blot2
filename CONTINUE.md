# Continue here

Finish the entire program in [tasks/README.md](tasks/README.md), continuing past
individual milestones. **Nothing is pushed.** Preserve private worktrees and old
artifacts; tasks 082/083 still require their distinct owner decisions.

## Qualified main

Compiler `121eb59` adds selected effect identities and strict-zip scalarization.
The latest full gate passes 1,688 native laws, 1,066 guest/client tests and
1,036 complete allocation-failure sweeps plus two expected-error sweep laws;
analyzer zero across 375 files.
[Merged qualification](zig-native/CONTINUATION_QUALIFICATION.md) records exact
behavior, failed/regressed runs and final measurements. There are 67 complete, 7
in progress and 26 pending tasks: 33 remain open.

- Frozen tree `7b19d7a427ab1cf2a798b60a07cf585ce85d6e12`; native source
  `adb955cc7c88209bc738b6246ec44bf83610a04c`.
- LLVM/Fast SHA-256:
  `9414b47707e14fd2818453a643113d275a497271e7d967fd4fc241d77b9b6642`. Main's
  ignored executable and compressed bundle match. Immutable evidence:
  `build/bench/continuation-20261013/selected-qualified-pins.json`.
- The preceding `ae001bb` batch's seven captured pairs against `38e822d`: fresh
  2225.518→1950.672 ms; edit 1247.822→906.212 ms; revert 1147.918→813.715 ms.
  Paired ratios 0.8767/0.7266/0.7084; exact Wasm and source fuel. Public CPU
  stays near parity, and all 62 packed-width outputs remain exact. Final task
  084 targets remain unmet.
- Latest seven captured pairs against `ae001bb` remain near parity: paired
  fresh/edit/revert CPU ratios 0.9980/0.9973/0.9988. Thirteen public programs
  and all 62 packed-width outputs retain exact Wasm. The release handshake and
  an independent fresh configure agree on compiler identity. Never copy another
  worktree's Zig configure cache as a qualification shortcut.
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
  2.899→0.030 ms at 4,096 rows. Windows still uses 81,894 objects; two runtime
  batches give ratios 1.0264 and 0.9868, so no window win is claimed. Growing
  primitive constants retain the earlier 28–53% retained CPU win at 512–2,048
  elements; captured constants still have zero receipt activity.
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
- **047:** The retained optimizer worklist and structured control-frame exit
  reachability are merged and fully qualified. Preserve frozen
  `/var/tmp/blot2-iterator-remainder-047`. Active
  `/var/tmp/blot2-iterator-windows-047` investigates explicit published root
  lifetimes; parameter representation alone grants no ownership authority.
  Windows remains unresolved. Prior owner-sharing/cost-prefix screens did not
  improve allocations and remain rejected.
- **058/059:** Selected identity terms are merged and fully qualified. A generic
  factory's `InvalidArtifact` failure was repaired by preserving exact origins
  across payload normalization; artifact validation remains exact. Active
  `/var/tmp/blot2-generative-effects-058` develops pure product parameter
  footprints with checked Core validation. General
  parameter/capture/result/store footprints, invocation binders,
  opaque/associated boundaries and lifetime contracts remain open.
- **070:** `/var/tmp/blot2-erased-proofs-070`, with staged base `d55ab1cd`, owns
  unmerged native proof syntax, exact typed value terms and public-contract
  validation. Patch/pins/remaining work:
  `build/bench/continuation-20261013/proof-consistency-foundation/` (patch
  SHA-256 `41db5de726d60c51c05763e2aa0c63a4b1da95b6208f055fa2a18363f9243439`).
  Focused native 26/26, full syntax 41/41, frontend 23/23, editor and analyzer
  377 files zero. Bounded SCC consistency replaces quadratic closure: 256
  requirements validate in 4,902 charged visits instead of exhausting 65,536.
  This is not a full compiler qualification. Keep ordinary data types and value
  identities separate; future 058/059 footprint contracts can reuse that value
  owner. Distinct proof-kind checking, constructor guards, compiled-body
  authority, erasure and checker integration remain unfinished. Frontend/editor
  syntax is implemented only in the isolated prototype. See
  [proof qualification](zig-native/NUMERIC_PROOF_QUALIFICATION.md). 071 waits
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
`/var/tmp/blot2-continuation-following-20261013`. Start the next integration
from current main and apply only later isolated deltas.

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

The latest gate took 933.29s: release build 203.61s, native compilation 298.96s,
native execution 396.76s and guests 21.39s. Focused preflight catches
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

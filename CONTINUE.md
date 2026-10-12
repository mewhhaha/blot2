# Continue here

The owner wants the entire program in [tasks/README.md](tasks/README.md)
finished. Continue past individual milestones. **Nothing is pushed.** Keep old
artifacts and private working trees; artifact deletion/pushing still require
their separate owner decisions.

## Qualified main

Latest compiler implementation:`4013b10`. Latest design:`07cbc62` (057). 045/046
are complete: ordinary rolling fold/monoid/group windows and opaque persistent
AVL summary build/get/query/set/concat. 057's scoped-effect design is complete;
058–059 are not implemented. Earlier completed milestones remain in the task
index and durable records.

- Qualified tree:`3688e1965213b06e36a1ad5118ab1c6f1c1de54b`; compiler source:
  `48f7bf8cd3219535013dd8eb96b28e0c67702bcd`.
- LLVM/Fast SHA-256:
  `44af80a95af5de58c521a7d520c5d8c6ea993e09aae1c06e9031f3d5dbd9ec2b`. Immutable
  executable: `build/bench/joint-024-035-045-046/blotc-release-candidate`.
- Full native/OOM and 961 guest/client tests pass, all eight unchanged budgets,
  351 analyzer files/zero, Zig 0.17.0.
- Seven public compiler pairs preserve diagnostics/work and per-binary output;
  CPU 0.9945–1.0234, peak deltas zero, teardown zero. Synthetic fresh/retained/
  restart bytes are exact. No general compiler gain is claimed.
- Widest scalar fast windows are about 11–12× faster. Summary build now scales
  linearly; exclusive Array updates remain cheaper. Current streams/updates are
  bounded; saved versions and real cyclic trials are charged. See
  [ROLLING_SUMMARIES_QUALIFICATION](zig-native/ROLLING_SUMMARIES_QUALIFICATION.md).
- This compiler also qualifies explicit-field receipts, conditional frames,
  static nullary constructors, Array-copy publication, single-use private
  physical storage and same-unit immutable acyclic proofs. 024/035 remain open.
  See [BODY_CUTOFF](zig-native/BODY_CUTOFF.md),
  [TRACING_REPLACEMENT](zig-native/TRACING_REPLACEMENT.md) and
  `build/bench/joint-024-035-045-046/qualification-pins.json`.

## Active work

Root owns the next 047 iterator/cursor hill. 058 is ready;053 still depends on
024. Take ready tasks in index order and keep task/index status together. A
successful subset never closes a broader gate.

- **035:** `/root/resolved_body_028` works in `/var/tmp/blot2-tracing-final-035`
  over frozen acyclic tree `d408a6f4`. Frame-retirement batching was rejected
  and preserved separately. A new exact direct named-reference environment
  removes one hot allocation/frame and two slots per cycle. Focused
  OOM/replay/static/multi-curry laws and old/new retirement controls pass;
  development cycle CPU improves about 12%, with mixed small controls. Final
  both-tier/compiler-cost checks and freeze remain. Do not port before handoff.
  Physical tracing removal, whole-module coverage and the historical tracing CPU
  gate remain open.
- **056:** `/root/associated_members_055` works in
  `/var/tmp/blot2-implementations-056-qualified` on 46 bf 8 b 9. Explicit impls,
  selected proof DAGs, methods/captures and transitive prerequisites have 52
  focused native/OOM laws. Checkpoint 126 is immutable, not a final handoff.
  Compatibility, diagnostic/source/compiled/restart parity and measured screens
  remain. Port only its final delta onto current main; preserve the dotted
  access guard.
- **086 is approved:** the owner accepted
  [CONSTANT_REUSE](zig-native/CONSTANT_REUSE.md) on 12 October 2026.
  `/root/demand_summary_036` owns it. Latest immutable development slice: tree
  `9455eedc`/`literal-floor-checkpoint.patch` under
  `build/bench/constant-receipts/`, based on 850793 f. Owned read/fuel/resource
  receipts keep principal work ordinary and decline escaping view publications.
  Literal scalar collections skip recording; matched scalar/Array edits improve
  about 1–2%, with explicit cold costs. Native/OOM,12 guests/eight budgets and
  353-file zero analyzer pass; no LLVM integration/final 086 claim.
- **086 next:** a fresh-only diagnostic identified collection-buffer publication
  followed by a real solver inside the dominant value computation. A growth-only
  expansion is held until that later inference judgment has an owned worthwhile
  boundary. Preserve discarded-tape diagnostics and frozen slices. The
  19645/compiler 2689 tree is historical; corrected work is in
  `/var/tmp/blot2-constant-reuse-current-086` and
  `/var/tmp/blot2-constant-inference-086`.
- **024:** captures still elaborate 80 edited-module bodies in the 93-unit
  project. Dotted paths, local requirements, producer ordinal relocation and the
  under 100 ms target remain. Agent 036 prioritizes 086 before returning here.
- **093:** ordinary authorized work; no further approval is required. Its
  owned-lifetime/hash design remains. Read-only 93-unit attribution:
  `build/bench/constant-receipts/current-profile-039.json` (about 1040 ms wall;
  constants 49 ms, inference 536 ms, lookup 84 ms). This changed corpus is not a
  comparison to the historical 400 ms input.

Agents do not edit main or run duplicate full gates. Root reviews frozen inputs
and runs one combined gate per commit-ready batch. Keep isolated, rejected and
merged release costs separate.

## Build and validation

- Check `zig version` before each build batch; use Zig 0.17.0.
- Incremental:`deno task build:compiler:dev`;
  release:`deno task build:compiler`.
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

bpm is complete at 2798 ff 9: Git/local/transitive exports, caching, exact
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

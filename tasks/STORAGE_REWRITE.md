# Owned-storage rewrite: active task index

The current priorities are shared-kernel runtime, Gdev Wasm size and short
iterations. Subsecond compilation, sub-five-second Main and 1–2MB remain unmet.
The
[current measured checkpoint](../benchmarks/goose/results/2026-11-04-sort-hills.md)
adds dominated fixed-array validation reuse, known scalar strides and guarded
bulk copy/fill loops. Unchanged merge/quick/Sieve improve **1.64 / 1.35 /
2.43x**; custom hash regresses **4–5%**. Main saves another **47,689B** to
**10,049,963B**. Fresh paired compilation is effectively unchanged at **5.55s**.
The independently newer Goose reference and all timing/size tradeoffs remain
explicit.

The latest
[checked merge checkpoint](../benchmarks/goose/results/2026-11-04-merge-select.md)
improves unchanged merge another 1.466x and narrows the fresh Goose gap to
1.36x. All bounds remain; source/carry proofs admit checked select/store
emission. All 2,953 native laws compile without LLVM, and the focused 8
native/28 guest family passes in 9.36s. Main remains byte-identical at
10,049,963B, with fresh paired compilation 5.271→5.279s. Full qualification
remains pending after an unexplained native-run cancellation; the checkpoint
preserves raw evidence.

The preceding
[feature retirement](../benchmarks/evidence/integration/2026-11-04-demand-retirement.json)
removes memoized `~` demands in favor of primitive Boolean operators and
ordinary Unit callbacks. All 2,949 native laws compile without LLVM; the
affected checks and baseline failures are recorded in that evidence. The final
function-syntax development family passes 8 native / 26 guests in 28.41s. Full
qualification remains pending. Three uncached release pairs measure 5.409 →
5.474s with byte-identical Main: no speed or Wasm-size gain from this deletion.
A fresh inspected NVIDIA frame matches the prior PNG/trace under original
budgets. Only Gdev's language compatibility test changes in the siblings; its
broad collection fixture retains the same admission failure on both compilers.

Keep `List T` and `[]` for immutable building, concatenation and traversal.
[The packed-sequence pilot](../docs/compiler/PACKED_SEQUENCES.md) models active
enum payloads and copied scalar tails; its standalone native witness is not yet
production compiler support. Task 112 must retain List behavior, borrowed views,
explicit copies and capacity failure semantics while changing representation.
Indexed mutation remains an Array operation. Measure actual live/reserved bytes
and source-level execution before accepting the packed backend.

Next measure representation work by record shape and operation, then compare
creation-backed immutable FrameAccess with shared semantic shapes/transitive
field demand. Main still spends 4.430s in the backend and requests 5.324GB
cumulatively; copy-only changes cannot reach the output target. Preserve the
[preceding shared hills](../benchmarks/goose/results/2026-11-04-shared-hills.md),
[recursion](../benchmarks/goose/results/2026-11-04-recursive-calls.md),
[addressed-input](../benchmarks/goose/results/2026-11-04-addressed-inputs.md),
[shared-call](../benchmarks/goose/results/2026-11-03-call-contexts.md) and
[fresh-owner](../benchmarks/goose/results/2026-11-03-fresh-owners.md) evidence,
including rejected rollouts and snapshot-specific qualifications.

The historical 2.08MB output was recovered from preserved inputs in a bounded
2.88s replay. Historical records used heap pointers; current transport moves
physical Value leaves and owner/borrow metadata. Remaining local/global
instructions occupied 8.54MB at that older checkpoint; the current census is
6.51MB. Preserve semantic checks and explicit copies while changing that
representation. Ordinary `#run` build functions remain a separate, unimplemented
simplification.

Read [CONTINUE.md](../CONTINUE.md) for the current compile frontier and exact
handoff evidence. The earlier candidate advanced through checked source
validation and one real Gdev main frame in native Pen, with all runner checks
and an inspected PNG. See
[the current migrated-frame candidate](../benchmarks/evidence/integration/2026-10-31-migrated-frame.json).
The final source/API inventories pass 760 valid files and six intended semantic
rejections across Ink/Gdev. Broader compiler, original-export, library/game and
host/browser qualification remain pending. Keep changing compile frontiers in
CONTINUE.md and its linked evidence. The earlier full compiler gate stopped at
its protocol smoke span assertion (three passed, one failed); see
[the handoff evidence](../benchmarks/evidence/integration/2026-10-30-full-gate.txt).

## First native frame — complete

The real main compiled and rendered one headless frame on 2026-10-31. Continue
the remaining qualification and greenfield backend/API retirement requirements
below; first-frame success does not establish full gameplay or performance.
Preserve source, assets and useful requirements across the existing siblings.

For an optional compile-only diagnostic with the matching native compiler:

```sh
deno run --no-config --no-lock -A scripts/integration/build_gdev.ts --timeout-ms 10000 > /tmp/gdev-main.log 2>&1
python3 scripts/integration/report.py /tmp/gdev-main.log
```

For actual integration, build matching Pen and plugin binaries, then run (the
default recompiles; `CONTINUE.md` documents verified artifact reuse):

```sh
python3 scripts/integration/run_pen.py --launch
```

The tracked runner requires successful exit, one frame trace, a completed render
marker and a 640×480 PNG. Inspect the image. Ignored build logs from another
machine are not prerequisites or current evidence.

## Frozen interfaces and unresolved work

- Guest ABI 8, session protocol 2, Gdev saved schema 26 and packet operation
  order.
- Named persistent pools, invocation-local frame owners and borrowed access
  records. Encode before owners close; host and worker boundaries copy packets.
- 2 MiB temporary, 256 KiB persistent, 2 MiB transport and 4096 owner slots.
- Presentation acknowledgement repairs caches; it does not implicitly restore
  simulation. Snapshot/Restore is explicit; a retry must not advance twice.
- Compile-known callbacks retain real effect rows and owner identities. Preserve
  strict checks and correlated private witnesses; do not thaw all private
  rigids.
- The scoped backend exists, but ordinary legacy backend retirement and general
  application qualification remain unfinished. Language tasks are retired in the
  target model; host workers and data queues remain.
- Backend nonfunction/global exports and the output block-break inference defect
  remain pending. Do not hide the scalar-export law with `#run`.

See [the ownership contract](../docs/compiler/SCOPED_STORAGE.md) and
[decision review](../docs/compiler/STORAGE_REWRITE_REVIEW.md). The
[historical integration log](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/STORAGE_REWRITE.md)
retains earlier batches and measurements; it is not a list of checks passed now.

## Tasks and handoffs

| Task                                                    | Result                                                                 | Implementation dependency                                                      |
| ------------------------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| [110](110-plan-owned-storage-and-specialized-calls.md)  | Storage plan, lifetime summaries and reusable destination calls        | First publish the plan/value/exit/call interfaces with 111/112                 |
| [111](111-pack-regions-and-widen-owner-identity.md)     | Packed regions, grower lanes and wide owner identities                 | 110 interface; may implement in parallel                                       |
| [112](112-admit-flat-data-and-control.md)               | ADTs, patterns, exits, loops and flat List operations                  | 110 interface and 111 runtime contract                                         |
| [113](113-initialize-pools-and-copy-host-packets.md)    | Computed persistent pools, copied packets and host suspension          | 110–112 interfaces                                                             |
| [114](114-replace-ink-storage-and-ecs.md)               | Owned collection/ECS APIs and explicit checkpoints                     | Shared target contract; write before compiler completion, accept after 110–113 |
| [115](115-migrate-ink-simulation.md)                    | Scene, physics, simulation and spatial ownership                       | 114 API handoff                                                                |
| [116](116-migrate-ink-render-and-ui.md)                 | Render/UI/input storage and known policies                             | 114 API handoff                                                                |
| [117](117-migrate-ink-application-lifetime.md)          | Live application, saves, history and native/browser protocol           | 114 API; coordinate 113 host ownership                                         |
| [118](118-migrate-gdev-systems.md)                      | Game systems using explicit pool access                                | 114/115/116 APIs and 119 owner schema                                          |
| [119](119-compose-gdev-owned-world.md)                  | Concrete world, static stages, devtools and integration                | 114/117 APIs; co-design with 118                                               |
| [120](120-retire-counted-storage-and-language-tasks.md) | Unconditional new backend; old runtime/task removal                    | Inventory early; cut over after 110–119 application execution                  |
| [121](121-qualify-and-measure-owned-applications.md)    | Final behavior qualification and separate compile/runtime measurements | 120; preserve baseline artifacts early                                         |

Dependencies mean a stable interface is needed to write code, not that every
upstream test must pass first. Acceptance waits for executable integration. Hand
off concrete type/function declarations and one representative call site; do not
create another design-only phase before implementing modules.

## Verification budget

1. Write a complete slice and its few semantic witnesses, then compile once.
   Failed compilation is repaired as a batch. No build/test invocation per small
   edit, no exhaustive OOM sweep per agent and no long generation soak.
2. Integrator checks `zig version` before each build batch: Zig 0.17.0.
   Development and native test compilation use `-Dllvm=false`, safe optimization
   and `--prefix zig-out-native-dev`. Use
   `deno task check:dev --area static-sharing` as the starting family and
   register only the affected new laws. It remains a development pass, not full
   qualification.
3. Reuse the installed native test inventory for exact laws. Group
   executed-Wasm, copied-host and worker witnesses. Consumer gates use the same
   compiler artifact; do not accidentally test the old `zig-out/bin/blotc`
   binary.
4. After coherent consumer batches, run the required Ink generation/format and
   tests, Gdev check/codegen/tests, and relevant Pen native/browser checks. Run
   GPU work sequentially and headlessly. Record baseline failures separately.
5. Final only: release compiler build for release guest/performance evidence,
   `deno task test:compiler` and `deno task lint:zig`. The full gate's native
   compilation still uses the native backend. No repeats after a pass without a
   changed candidate, concrete failure or unresolved concern.

Acceptance bullets identify distinct behavior, not a demand for separate test
programs or separate builds. Reuse existing fixtures where they cover the new
contract; replace obsolete COW/task expectations intentionally. Never mark an
incomplete run or compiled-but-unexecuted inventory as a pass.

## Completion and performance

Update each task and this index when code lands in the workspace, distinguishing
implemented, development-checked and qualified. Keep the durable decision and
final evidence under `compiler/`. Task 999 cannot run while any task here is
unfinished and does not itself authorize a cleanup now.

Keep baseline source/binary identities before retirement. Measure fresh compile,
retained edits, precompiled warmed simulation, packet/presentation cost, Wasm
size and memory separately. Preserve meaningful gameplay/save witnesses; do not
infer frame time from the test-suite duration. Report results even if the hoped
for improvement fails to appear. Do not introduce a benchmark-optimization loop
until an actual regression or missed goal points to specific code.

## Earlier program

The [task navigation](README.md) retains the relationship to the earlier
program. Tasks 110–121 are unfinished. Documentation reorganization does not
complete them or satisfy task 999. Checkpoint commits and pushes follow the
current owner instructions in `AGENTS.md`; environment publication is separate.

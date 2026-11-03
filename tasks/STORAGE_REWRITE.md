# Owned-storage rewrite: active task index

The current priorities are shared-kernel runtime and Gdev Wasm size, with short
iterations. Subsecond compilation remains the goal; the next latency gate is
below five seconds. The
[shared-call checkpoint](../scripts/bench/goose/results/2026-11-03-call-contexts.md)
imports initialized source globals through checked implicit owner roles with
cached dependency footprints. Exact immutable input equality propagates into
nested planning, completed physical demand selects the existing 512-parameter
ABI, and concrete callback qualifiers retain their certificates without forcing
expansion. ABI 8/session protocol 2 and fresh-owner lifetime contracts remain.

Current paired Main medians are **5.634 → 5.278s**, Wasm **12,113,691 →
10,241,074B (15.5%)**, rollbacks **1,464 → 577**, discarded expressions
**108,775 → 75,786**. Each pair improves 312/334/376ms; the median paired
reduction is 334ms. Local/global instructions still occupy 6.69MB. A separate
profile has backend 4.404s/5.21GB cumulative requests, peak process RSS 1.05GiB.
The five-second, subsecond and 1–2MB targets remain unmet.

All 2,969 native laws compile without LLVM; affected families pass 405 unique
native laws. Eleven focused laws pass full-fault mode. Release guests pass
284/286; unsupported ECS summary-job export and legacy optimized iter.take(0)
also fail on the frozen baseline. Full gate passes 49 smoke/57 harness checks,
then stops at 180s after 100 native laws, zero failures/leaks/logged errors.
Full qualification remains incomplete. Zig lint/format/type checks pass.

World/editor and seven renderer streams match; small hand/renderer binaries
grow. The final Main's inspected NVIDIA PNG and guest trace match the baseline
exactly; see
[frame evidence](storage-handoff-evidence/2026-11-03-call-contexts-frame.json).
Broader gameplay/software-adapter coverage remains pending. Gdev `38af070`
captures one hook environment; Ink/Pen and all assets are unchanged. The
32-shape capture matrix shrinks shared environments up to 41.8% but its largest
distinct-owner control nearly doubles; preserve that regression. Next measure
immutable addressed bundles across calls, with complete semantic facts, snapshot
behavior and invocation lifetimes. The rejected all-global context prototype and
landed single-dispatcher source patch remain pinned in the report. Preserve
earlier
[fresh-owner evidence](../scripts/bench/goose/results/2026-11-03-fresh-owners.md)
and [survey controls](../scripts/bench/goose/results/2026-11-03-expanded.md).

The historical 2.08MB output was recovered from preserved inputs in a bounded
2.88s replay. Historical records used heap pointers; current transport moves
physical Value leaves and owner/borrow metadata. Remaining local/global
instructions occupied 8.54MB at that older checkpoint; the current census is
6.69MB. Preserve semantic checks and explicit copies while changing that
representation. Ordinary `#run` build functions remain a separate, unimplemented
simplification.

Read [CONTINUE.md](../CONTINUE.md) for the current compile frontier and exact
handoff evidence. The earlier candidate advanced through checked source
validation and one real Gdev main frame in native Pen, with all runner checks
and an inspected PNG. See
[the current migrated-frame candidate](storage-handoff-evidence/2026-10-31-migrated-frame.json).
The final source/API inventories pass 760 valid files and six intended semantic
rejections across Ink/Gdev. Broader compiler, original-export, library/game and
host/browser qualification remain pending. Keep changing compile frontiers in
CONTINUE.md and its linked evidence. The earlier full compiler gate stopped at
its protocol smoke span assertion (three passed, one failed); see
[the handoff evidence](storage-handoff-evidence/2026-10-30-full-gate.txt).

## First native frame — complete

The real main compiled and rendered one headless frame on 2026-10-31. Continue
the remaining qualification and greenfield backend/API retirement requirements
below; first-frame success does not establish full gameplay or performance.
Preserve source, assets and useful requirements across the existing siblings.

For an optional compile-only diagnostic with the matching native compiler:

```sh
deno run --no-config --no-lock -A scripts/storage_handoff/build_gdev.ts > /tmp/gdev-main.log 2>&1
python3 scripts/storage_handoff/report.py /tmp/gdev-main.log
```

For actual integration, build matching Pen and plugin binaries, then run (the
default recompiles; `CONTINUE.md` documents verified artifact reuse):

```sh
python3 scripts/storage_handoff/run_pen.py --launch
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

See [the ownership contract](../zig-native/SCOPED_STORAGE.md) and
[decision review](../zig-native/STORAGE_REWRITE_REVIEW.md). The
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
final evidence under `zig-native/`. Task 999 cannot run while any task here is
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

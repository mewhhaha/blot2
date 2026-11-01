# Owned-storage rewrite: active task index

The active priority is subsecond Gdev compilation with bounded iteration.
[Scoped validation batches and list-copy deletion](../zig-native/measurements/checker-validation-reduction-2026-11-01.json)
improve matched fresh World-producer validation 883 to 693 ms and total 7.69 to
7.41 seconds. Checking improves only 1.5%; the ineffective nominal memo and
application guards were removed and archived. Astra's next discriminator is
cursor-aware ordinary-type reads across application/pending-use checking, with
the same depth/history/effect laws and a 20% checking gate.
[Completed producer-validation receipts](../zig-native/measurements/completed-core-validation-2026-11-01.json)
remove one repeated semantic traversal with exact Snapshot/context authority:
world-producer medians improve 8.63 to 7.78 seconds with identical tiny output.
Whole-main remains over five seconds. Larger automatic copy plans and nominal
world interfaces missed their gates and were removed; their evidence is linked
from CONTINUE.md. The
[opaque draw-batch prototype](../zig-native/measurements/unqualified-draw-batches-2026-11-01.json)
stopped at unsupported escape/control shapes before performance measurement.
[The completed-child unification experiment](../zig-native/measurements/rejected-completed-unification-2026-11-01.json)
missed its 20% checking gate and was removed. The
[bounded CPU profile](../zig-native/measurements/normalization-cpu-attribution-2026-11-01.json)
now places normalization across application/finish paths; audit actual
historical observations before changing the shared inference representation.
[Engine-boundary measurements](../zig-native/measurements/engine-boundary-experiments-2026-11-01.json)
now retain incomplete profiles and distinguish checker jobs, backend stages and
optimizer pass costs. Closed leaf-call plans and two small source-interface
experiments missed their thresholds and were removed/rejected. Task 110 remains
unfinished. A direct-destination original kite producer passes seven complete
[stream comparisons](../zig-native/measurements/kites-destination-streams-2026-11-01.json),
saving 1,014 Wasm bytes; whole-main compilation/frame qualification is pending.
The scalar, concrete-field, nominal and descriptor-call batches have measured
synthetic gains. Proof-instance reuse and shared type transformations remove two
exponential source cliffs; whole-game compilation still exceeds the bounded
diagnostics. See
[the graph-sharing evidence](../zig-native/measurements/proof-and-type-sharing-2026-11-01.json)
and
[exact receipt hashing](../zig-native/measurements/receipt-path-hashing-2026-11-01.json)
and
[closed array locals](../zig-native/measurements/closed-array-locals-2026-11-01.json)
and
[actual aggregate readers](../zig-native/measurements/aggregate-reader-sharing-2026-11-01.json).
Selected-address loads remove wide-row amplification in
[actual render settings](../zig-native/measurements/selected-field-loads-2026-11-01.json).
Owned assembly now honors tier, worker and sharing controls and reports
[actual optimizer work](../zig-native/measurements/owned-assembly-options-2026-11-01.json).
[Typed call sharing](../zig-native/measurements/typed-call-sharing-2026-11-01.json)
now covers literal closures across shared parents and canonical plain input
keys. Real closure/easing probes shrink; whole-game completion remains pending.
The
[LLVM release attempt](../zig-native/measurements/typed-call-release-attempt-2026-11-01.json)
is incomplete;
[native-fast diagnostics](../zig-native/measurements/native-fast-diagnostic-2026-11-01.json)
remain separate from full qualification. A
[bounded main stack sample](../zig-native/measurements/gdev-checking-sample-2026-11-01.json)
observes source type instantiation before assembly; it is not a completed build.
The
[type-structure experiment](../zig-native/measurements/type-structure-experiment-2026-11-01.json)
rejects ineffective substitution copying changes and attributes actual producer
work. The new counters do not establish a frontend speedup. The
[corrected lazy demand inventory](../zig-native/measurements/lazy-declaration-demand-2026-11-01.json)
is diagnostic only; source checking remains exhaustive. Unused-heavy entry
points expose large body-demand reductions; main still retains most body bytes.
Read [CONTINUE.md](../CONTINUE.md). Do not repeat an unbounded main build.

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

# Cloud continuation qualification, 19 October 2026

The continuation uses Zig 0.17.0 and Deno 2.9.6. Heavy commands share a lock and
a 14 GiB process-tree RSS limit. The compiler is an LLVM release build;
development screens are identified separately.

## Compiler gate

Qualified compiler/source milestone: `e29dd0d2c6faa2ad16a39e4a06ef254cede3ff2c`
on local `main`. Later documentation-only recording commits preserve its native
inputs.

The forced complete run passes:
`deno task test:compiler --resume --force-native --budget-seconds 7200
--phase-seconds 5400 --jobs 2 --build-jobs 2 --native-shards 2`.
Logs are in ignored `build/bench/iteration/run-cfd5c1f6733154b7/`.

| Check                                      | Result                                                       |
| ------------------------------------------ | ------------------------------------------------------------ |
| Native laws                                | 2,470 executed; zero skips, failures, leaks or logged errors |
| Guest/client checks                        | 1,556 passed; zero failures, errors or skips                 |
| Harness checks                             | 37 passed                                                    |
| Release build, package and publish dry run | Passed; no publication                                       |

The two native shards each execute 1,235 laws. Native execution takes 1,368.35
seconds and guest execution 429.47 seconds on this instance. The preceding
`run-246325b3c106a1ed` used Zig's own run cache and is not counted as new native
execution. The repaired gate refuses to record or reuse a native run cache hit
as journal evidence. A full run without verified journal reuse forces execution
and records source, toolchain-file, binary and log hashes inside its own
environment. The strict journal key still includes the whole environment;
inspection compares that saved key instead of recomputing an environment hash in
a different shell. Native journal/process regressions pass.

The current native input digest is
`61282b7e52f245fb3798d20ed7fea84b7b06379fa2a1ac7868040ff9b84a60a4`; the executed
test binary SHA-256 is
`1008c2dfb2805fdcf5a6af78b77c35fdd4c3146c9b95c7a787a15a12889de6f9`. The complete
working-tree source/output pins are in
`build/bench/task024-final-qualification/qualified-pins.json`.

The release compiler SHA-256 is
`0f531509c7316dfb318510c668152f4c2bdbb48d188863f1d4c3d82362823aa3`. Earlier CT90
and field-only binaries and their evidence remain separate.

## Law coverage

The gate includes the row-to-law maps in [body cutoff](BODY_CUTOFF.md),
[typed staging](STAGING_QUALIFICATION.md) and
[structured tasks](STRUCTURED_TASK_QUALIFICATION.md). In particular, it runs the
new declared-field/qualified-root allocation-failure law, splice usage and
live-skolem rejection laws, and scoped Task callback/package rejection laws. The
new guest groups check both codegen tiers, fresh byte equality, executed
results, rejection without artifact publication, correction and retained output
after failure.

The whole production suite also reruns the existing evaluator/Core/checker/
backend ownership laws, relocated fixture consumers, generalized-local
instances, nested rebinding, static captured callback rows and Array loop
ownership laws. This common execution qualifies their current behavior; dated
before/after measurements in their own records remain historical measurements.

## Protocol fixtures

Transport tests prepare the existing TypeScript peer as a cached Deno
executable. Cancellation and deadline LSP laws use a small native Zig peer,
prepared before the timed requests. Its held generation waits for process
cancellation; a replacement generation answers immediately. Cache keys include
source, helper, target and toolchain version. Production timeouts and test
assertions are unchanged. All 77 LSP/transport/format checks also pass together
with two workers. Generated peers remain in ignored `build/tests/`.

## Relocated inputs and source structure

The fixture audit compares Git blobs and working-file SHA-256 values. All 130
data inputs are unchanged since `23a934f`. Of these, 126 have byte-identical
predecessors in `23a934f^`; two package inputs, the provider lifetime-cost input
and the effectful dictionary-closure input were added or edited during that
integration. The test-only `fixtures/root.zig` is a separate catalog module. The
full manifest is `build/bench/task079-fixture-audit.json`.

Current evaluator expression/collection dispatches are 113/76 lines, and checker
expression/statement dispatches are 46/19. The checker's lifecycle coordinator
is still 417 lines. Compilation entry wrappers are not counted as substantial
routine reductions. The responsibility boundaries are documented in
[evaluator ownership](EVALUATOR_OWNERSHIP.md),
[Core ownership](CORE_OWNERSHIP.md), [checker ownership](CHECKER_OWNERSHIP.md),
[backend ownership](BACKEND_OWNERSHIP.md) and [source areas](SOURCE_AREAS.md).

## Paired compiler comparison and CI analyzer

### Current workload pin

Task 084's current workload is the owner-approved recreated freeze at
`build/bench/gdev-snapshot`: gdev `52fbc5af4ba4accf5559d87e2fffed335fa920ad` and
Ink `1a291a1b90b9197e6a9fc327f52d77bf965d8cf3`, with 583 files and 69 test
entries. The committed [input manifest](../scripts/bench/gdev-manifest.json) has
SHA-256 `4689301ed5ef13f9cce244a474fbe353ebfeceeb072101c85f6663995e0b0728`; the
[output references](../scripts/bench/gdev-wasm.json) have SHA-256
`8054af76dff612509f04006626163ad5646e77ce7b52d097e97f09be45e64492`. The
benchmark verifies every input before measuring. Private source remains ignored;
historical measurements on the lost freeze are separate workloads. This pin also
supplies task 086's measurement workload. Its seven-pair constant-cost decision
and task 084's remaining qualification are still open.

### Current comparison

The preserved baseline executable has SHA-256
`807d3f05f1a884290014d6b698f2263faa938e072df3cdbf4feca1b53f60584e`. Against it,
strict comparison passes for three alternating game/devtools pairs and one pair
each of goals_game, interface_station, edit, robot_pickup and protocol. Fresh,
retained, restart and shared-session output agrees, including the recorded
references and the pre-existing protocol rejection. No output difference is
declared. The source manifest and historical measurements remain separate from
the owner-approved recreated snapshot; this campaign does not re-execute every
private game test.

The seven-pair fresh game CPU guard uses one codegen worker and CPU affinity 0.
Candidate/baseline ratios are 0.941, 0.722, 1.118, 1.016, 0.892, 0.893 and
1.022; the median 0.941 passes the 1.05 limit. Individual pairs vary too much
for a speedup claim. The earlier failed unpinned identity control remains in
[COMPILE_GUARDS.md](COMPILE_GUARDS.md). Raw comparison and CPU records are
`build/bench/task024-final-comparison/results.json` and
`build/bench/task024-final-cpu/results.json`.

CI-pinned analyzer lint passes all 507 source files and the fixture module with
zero findings. Current runtime and staging measurements are recorded in
[tracing replacement](TRACING_REPLACEMENT.md) and
[staging qualification](STAGING_QUALIFICATION.md).

## Remaining qualification

A local analyzer at `9a78ce1` and its backend build. The published
`codeberg.org` rule is now active in enforced revision 4, and Git resolves Zig
0.17.0 to the expected commit `7647adab80dd088f4de3610fd245915a912eb6ad`. The
supported `-Duse-llvm=true` host compiler option builds the analyzer backend;
the resulting backend still uses `-Denable-llvm=false`. Its source, analysis
patch and protocol checks remain exact. Doctor reports Zig 0.17.0 and a
compatible backend. The analyzer binary SHA-256 is
`1ff727d14e0e6d75f882d6b9decdae9cab657a4815cff4d7703069aa0b4d4b25`, and the
backend executable SHA-256 is
`010850fcfe0ec617d2477ff5f7beca4edfbfa88536ad97ccea549cd0a0183c2c`. The
manifest's `backend_sha256` names its source/patch inputs, not the executable.
The earlier revision-3 rejection is retained as historical evidence in ignored
`.tools/published-network-observation.json`. The forced gate above qualifies the
earlier source milestone. New module-cutoff source changes require a new gate.
The local analyzer gate and the remaining module, iterator and final performance
requirements stay open.

## Current external and tooling checks

Task 109's
[current Array throughput qualification](PERSISTENT_ROOTS.md#current-array-throughput-qualification-19-october-2026)
passes the recovered original issue source and Ink's four probes against
historical `86a527b` and `48eda0a` releases. All required current/pinned ratios
are below 1.5, break writes scale by 1.821 when the count doubles, and 60,480
guest calls preserve witnesses and warmed memory. Each compiler uses its own
standard library and guest API. The production compiler is unchanged from the
full gate above. The callback qualification below brings the program to 97
complete tasks and 13 open.

Task 108 closes on the same qualified production compiler with owner-approved
recreated full-Ink inputs. Its 1,854 result checks pass in both guest codegen
tiers, including retained edit/revert and fresh-byte parity. The exact pre-fix
parent `05401a9`, built with Zig 0.17.0 in development mode and its own standard
library, reports `effect_mismatch` for the pure stored callback cases. See
[stored callback captures](STATIC_CAPTURE_ROWS.md) for pins, commands and the
scope of the memory observations. New task-053 compiler changes are separate
unqualified work.

The public Ink app-hooks input at Ink `1a291a1b90b9197e6a9fc327f52d77bf965d8cf3`
passes `scripts/bench_ink_acceptance.ts` with the release compiler in both
codegen tiers. Each tier executes 1,000 calls each to `paused_frame`,
`pause_events` and `schedule_workload`, checking complete event/result
witnesses. Committed guest memory stays at 131,072 bytes across all 3,000 calls
per tier. Input, harness and Wasm hashes are in
`build/bench/task105-ink-current/results.json`. The previous unpatched failures
and the conservative generalized-local limits remain recorded in the ownership
contract and task history.

Independent subsystem inventories discover exactly the same 2,470 unique tests
as the full production suite: syntax 133, types 105, runtime 186, checker 1,226,
evaluator 601, backend 575 and retained 1,061 (subsystems overlap). Three
exact-name relocated fixture consumers also execute with zero skips, failures,
leaks or logged errors. These inventory/filter builds use separate installation
prefixes and do not replace the full gate's executable.

All six Helix configuration checks pass. With tree-sitter CLI 0.27.1 installed
in a separate local tools prefix, grammar generation, the grammar corpus and all
seven example parses pass. The CLI install does not replace Deno's tools prefix.
Logs are `/workspace/.tools/current-editor-grammar-installed.log` and
`current-native-inventory.log` beside it.

The current heap observation is reproducible with `scripts/bench_guest_heap.ts`:
1,024/2,048/4,096/8,192 inner Arrays commit 192/256/384/640 KiB. At 4,096 the
block histogram is 4,096 × 48 bytes for inner Arrays, nine × 4,096 bytes for
journals and one × 32,768 bytes for the outer Array, totaling 260 KiB above the
reserved first page. The scalar checksum reads every row. Telemetry adds exports
only, and a memory-export-only control has the same checksum and committed
pages. Histograms include retired and recycled blocks; requested payload, block
high-water and committed pages are separate. See [shared RC](SHARED_RC.md) and
`build/bench/task106-current/results.json`.

The local GDB profiler smoke passes with one codegen worker: 867 sampling stops,
population plus four retained edit/revert builds, exact compiler/harness pins,
phase/receipt records and per-thread scheduler CPU deltas. Its ordinary report
is explicitly an unweighted stack inventory, which includes idle threads; it
must not be read as a CPU percentage. This smoke is not task 086's seven-pair
constant-cost decision. Population and build timing records remain in
`build/bench/task086-profiler-weighted-smoke/`.

## Runtime and measurement screens, 20 October 2026

These screens use the LLVM release from local `4fda7c2`, SHA-256
`1b05518e501b001a972a1815379aa433d697807a6084da3358a3464dd342d294`. Its
[task 053 qualification](MODULE_ABSTRACTION_QUALIFICATION.md#final-task-053-qualification-20-october-2026)
is complete. The screens below are narrower observations; they do not complete
R4, task 047, task 086 or the whole program.

The pure partial-application screen compares `value |> (add index)`, an ordinary
`pass value (add index)` helper and direct `add index value`. Both codegen tiers
execute counts 0, 1, 256 and 2,048, with 100 measured calls per case (2,400
measured calls). Witnesses, zero post-call roots/leases, stable warmed memory
and exact recovery after a rejected edit pass.

| Codegen tier | Pipeline / ordinary helper, rounded bytes per iteration | Direct call, rounded bytes per iteration |
| ------------ | ------------------------------------------------------: | ---------------------------------------: |
| Optimized    |                                                   0 / 0 |                                        0 |
| Development  |                                                 96 / 96 |                                        0 |

Development pipeline/helper traffic also records one retain, three releases and
two destructions per iteration; committed memory stays at 128 KiB in every case.
These are rounded allocator traffic and committed pages, not requested payload,
live bytes, CPU time or a general closure result. The original R4 statement
needs this tier distinction. Broader/effectful forms remain open.

The invalid expression `transform - value`, with `transform: F32 -> F32` and
`value: F32`, still rejects at **emit** with `unresolved_type` and "Code
emission requires concrete representation evidence" in both tiers. Moving that
diagnostic to the operator's checker remains open. Reinstating the valid source
restores byte-identical output. Results and script/compiler/input pins:
`build/bench/runtime-open-screen-v2/results.json`, SHA-256
`a79852da335b654ddf7413b7dcc2f585d75d3638898d186b2bf174467c1fc128`.

Callgrind 3.24.0 also completes a real synthetic List compilation on this exact
release with persistence disabled. It records **32,958,570 simulated userspace
Ir**, exact instrumented/control Wasm and compiler allocation counters, five
executed witnesses and zero final compiler live bytes. The count includes
startup, compilation and teardown. It is tool readiness on one small input, not
hardware retired instructions or pinned-workload CPU/instruction evidence.
Results: `build/bench/instruction-counter-smoke/results.json`; the Callgrind
output has SHA-256
`abaa942baf83c516759247933e17a7163146a349e4e983c0ae31f0bdde945cde`.

## Workload syntax migration, 23 October 2026

The recreated 583-file freeze was verified against the previous manifest before
migration. A lexical-only migration changes 4,510 `return` keywords in 218 files
to `break`, preserving the old nearest-`do` meaning after the language
migration. The real frontend lexer checked the changed tokens; comments, strings
and intrinsics were preserved. Private source remains in ignored benchmark
storage. The migrated manifest SHA-256 is
`60e11cc0c22ba75b4c5bb892f02a3509d9835a710036874aad360fa09b19a030`. Both the
main release baseline and the pre-numeric integrated release candidate pass all
seven fresh/edit/revert controls on that migrated freeze. Their final combined
candidate performance and runtime qualification remain pending; this manifest
migration is not a waiver of output or performance gates.

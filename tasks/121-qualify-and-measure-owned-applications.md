# 121 — Qualify and measure the owned applications

- **Status:** Pending; no new execution or performance evidence claimed.
- **Dependencies:** 120 final candidate. Preserve baseline artifacts before
  retirement; do not rebuild the baseline after deleting its implementation.
- **Contract:** [Review](../zig-native/STORAGE_REWRITE_REVIEW.md),
  [schedule and gates](STORAGE_REWRITE.md).

## Outcome and ownership

Report whether the replacement works across Blot, Pen, Ink and Gdev and whether
it saves actual compilation time, runtime time and memory. Keep those quantities
separate. This task owns benchmark/gate configuration and durable evidence;
source fixes go to the relevant task owner, followed only by affected rechecks.

## Execute once on a coherent candidate

- [ ] Record baseline/candidate compiler, host, standard library and consumer
  source identities, including uncommitted changes. Keep private Gdev source
  outside public commits; durable reports contain hashes and measurements.
- [ ] Check `zig version` (0.17.0). Run the final compiler gate and zero-finding
  Zig lint. Native tests compile with `-Dllvm=false`; LLVM is for the final
  release compiler and release performance measurements. Record exact executed
  inventory and failures, not just compilation success.
- [ ] Finish the required Ink/Gdev formatting, generation, compilation and
  behavior checks against that artifact. Reuse unchanged consumer evidence from
  checkpoint 3 only if the final candidate and all observed inputs match;
  retirement normally requires replay on the final compiler.
- [ ] Group browser/Pen transport, JSPI settlement/rejection, reentry/dispose,
  persistent state, protocol rejection, explicit save/restore and prepared
  worker recovery checks. Keep one/four worker coverage. A failed worker may be
  recreated; do not claim its partially mutated state survives recreation.
- [ ] Run bounded deterministic gameplay/save/replay and headless render
  witnesses, then measure the final release compiler/runtime. Do not introduce
  a long soak when seeded boundary tests prove generation/capacity behavior.

## Measurement contract

| Metric | Boundary |
| --- | --- |
| Fresh compilation | Game and devtools separately; wall and compiler CPU; identify cold process/cache conditions |
| Retained edits | No-op, literal edit and body edit; report separately from fresh builds |
| Precompiled runtime | Compile/instantiate/warm up before timing; fixed seed, input trace, timestep and frame count |
| Simulation and presentation | Separate guest update, packet encoding/copy and host rendering where observable |
| Memory | Used payload, metadata, reserved/committed Wasm bytes and peak host memory; avoid treating them as one measure |
| Work/output | Wasm size, deterministic state/save witness and changed scene/packet behavior |

Use a small fixed number of paired baseline/candidate samples (five alternating
pairs to start), recording all samples and spread. If the comparison changes
representation, compare semantic state witnesses rather than requiring identical
Wasm bytes. Do not rerun indefinitely seeking significance; report noise or an
unavailable baseline explicitly. Release compiler measurements must not be
presented as development-backend speed, or vice versa.

The earlier 15.61-second Gdev compilation and 189.7-second test suite are
historical, differently scoped evidence. Neither is a gameplay frame-time
baseline. Worker fixture memory likewise is not Gdev world memory.

## Completion

- [ ] Required behavior checks pass or a specific remaining failure keeps the
  affected requirement open. A partial run never closes full qualification.
- [ ] Durable report under `zig-native/` links candidate/source identities,
  concise commands, results, raw local evidence locations and limitations.
- [ ] Tables report before/after compile, runtime and memory results without
  inferring gains from architecture alone. If a meaningful gain is absent,
  identify the measured remaining cost instead of claiming the goal achieved.
- [ ] Update the task index, executable guide and active completion notes.
  No commit or push is requested here; the full gate is required before a later
  requested compiler commit. Task-directory cleanup remains a separate action.

## Evidence

Pending. The source review and task files are not benchmark results.

# Retained assembly worklist

This task 047 checkpoint removes repeated whole-module invalidation scans from
optimized-body matching. It does not complete the remaining iterator state and
cursor allocation work.

The frozen control is `52b6c36abad5f25f589fb0a6ba0e17d0e681f090`, reconstructed
from `59fcd6bcdf32ea4091942cd22ec51b3964d91952` and the parent's frozen source
patch. The captured workflow loads 93 units from the gdev snapshot, changes
`floor_half_extent` from 60 to 61, reverts it, then requests an unchanged build.
Diagnostic evidence and measurements live under `build/bench/retained-matcher/`
in the isolated qualification tree.

## Cause and bounded repair

The first owning assembly correctly rejects the previous plain-body capture:
root mode, root requirement and 33 root slots differ. A late ownership proof
failure then repeats assembly without owning roots. That context matches the
previous plain capture, and its 2,864 optimizer queries are complete. Neither
query saturation nor stale context explains the zero reuse in this second pass.

The old positional fixed point spends its one-million-unit relocation budget on
its second whole-module dependency scan and clears all positions. It then tries
50,908 relocation candidates with no work left. The new path scans exact local
observations once and builds bounded callee-to-caller edges. Every newly invalid
caller enters the pending worklist once. A clean module skips graph storage; a
context mismatch skips local comparisons; an unsealed query table still declines
reuse. Exhaustion still clears positional admission, and the remaining
relocation path stops when its shared budget is exhausted.

The production counters `match_candidates`, `match_work` and
`match_budget_exhausted` report the final assembly pass. They count positional
checks and relocation trials, charged shared work, and exhausted budget. The
portable optimizer interpretation changes to version 22, so older optional
captures cannot silently claim the new interpretation.

## Correctness evidence

The long-chain law changes a leaf below 191 callers and preserves seven
independent bodies. It checks retained/fresh byte parity, revert parity,
immutable prior inputs and complete matcher allocator-failure handling. A second
complete failure sweep checks ordinary fallback byte parity and reuse while a
dynamic allocation remains in the emitted body. Existing laws cover recursive
graphs, imports, globals, signatures, ownership observations, symbolic table
references, relocation, saturated queries and portable capture decoding.

The executed guest law edits a callee, reverts it, requests an unchanged build,
and restores a checkpoint before another edit. Both codegen tiers agree with
fresh bytes and execute the new answers at zero, small and larger iteration
counts. Existing iterator, private cursor, static constructor, project protocol
and allocation-budget guests are retained as controls.

## Release qualification

Zig 0.17.0 LLVM/Fast compiler SHA-256:
`2bfb2652936fd433349722ceb5353608d99b177f3cb24e4beb85e7e4ae4deef3`. Compiler
identity: `71cb1239d872b44c35532205f6a04a2c807242651f267a559d50b8a9199a6d0a`.
The qualified control executable is
`bbf4fb62168a056aa3b55b439c2a509cd0781e2d691f000a809e09ec1bcbd9a3`, identity
`f30ac9b0d7fcebc46682abf05ead45eadeed8d01cb6faff3f955b9df927adaba`.

Seven alternating captured pairs ran on CPU 6 with restart caches disabled. All
fresh, retained, edit, revert and unchanged outputs agree across compilers;
source fuel is 70,330 for actual builds and zero for unchanged builds. Edited
and reverted captures optimize two bodies and reuse 2,862, with 2,867 candidate
checks, 820,898 charged work units and no budget exhaustion. Retained capture
bytes remain 7,617,534.

| Phase     | Control CPU ms | Candidate CPU ms | Median paired CPU ratio | Control assembly ms | Candidate assembly ms |
| --------- | -------------: | ---------------: | ----------------------: | ------------------: | --------------------: |
| Fresh     |       2229.409 |         2257.502 |                  1.0126 |             177.944 |               176.292 |
| Edit      |       1255.653 |         1198.319 |                  0.9610 |             189.922 |               132.317 |
| Revert    |       1150.435 |         1114.099 |                  0.9556 |             184.547 |               129.228 |
| Unchanged |          7.374 |            7.585 |                  1.0368 |                   0 |                     0 |

The seven-pair synthetic adapter control has CPU ratios 0.9988 populate, 0.9889
edit, 0.9960 revert and 1.0028 unchanged. Thirteen public cold compile controls
preserve bytes and have median CPU ratios 0.9888–1.0162. This is an iteration
win on the captured fallback path; fresh and unchanged costs remain explicit,
and no general compiler speedup is claimed.

All 62 U32/F32 record/tuple packed-width modules are byte-identical to the
qualified control. All 124 instrumented fold/cursor allocation and answer pairs
agree, with root and lease cleanup checks. Identical machine bytes preserve the
prior packed execution qualification; no new packed runtime improvement is
claimed.

Focused qualification passes 39 native optimizer/archive laws, seven complete
allocator-failure sweeps (7,684 failure points), 69 existing development guest
laws/budgets, the new both-tier executed checkpoint law on development and LLVM
compilers, and 374 analyzer files with zero findings. The parent owns the
combined full native/guest/OOM gate; this checkpoint does not claim it.

`captured-release/pairs.partial.json` contains all 56 checked samples. The
harness's final optional Deno `/proc/loadavg` read was denied after every pair
completed. The original failure log remains; `pairs.json` was finalized from
those complete persisted samples in Python, without repeating measurements.
Immutable tree/source/patch pins and control artifacts are recorded beside it in
`build/bench/retained-matcher/PINS.json`.

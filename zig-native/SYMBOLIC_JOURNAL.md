# Compact symbolic instruction journal

23 October 2026. Qualified compiler change `86480d8` reduces the temporary
representation used while capturing emitted Wasm. The source change does not
alter instructions, resource ordering, admission checks or generated Wasm.

Consecutive instructions share one chronological event. A separate compact
array retains every symbolic operand. Runs stop at function, job, resource and
metadata boundaries, while the shared clock still advances for each instruction.
Publication transfers payloads into one function-indexed array and releases the
temporary array. Replay remaps every operand. Admission rejects invalid spans,
function IDs and clock overlap before publishing anything. Individual legacy
instruction records remain readable; allocation failures release partial owners.

## Qualification

The complete gate passed **2,527 exhaustive native laws and 1,640 guest/client
checks**, with no native skips, leaks or logged errors. Total gate time was
1,144.99 seconds, including 1,051.02 seconds of native execution. The development
build and native test compilation used Zig 0.17's native backend. LLVM was used
for the release compiler and paired application measurements.

Seven paired LLVM comparisons covered the frozen 583-file gdev workload, game,
devtools, edit suite, application tests, retained edits, reverts and restart
caches. All output comparisons passed, with no unexpected differences. The
fresh-game CPU guard passed: paired median **1.01083**, limit **1.05**. Individual
ratios were 1.01083, 1.08969, 0.89097, 1.00253, 1.03503, 1.06111 and 0.95262.
This supports accepting the memory change; it does not establish a CPU speedup.
Fresh-game medians were 3,474.50 ms before and 3,481.50 ms after.

The independent native-backend screening pair preserved exact fresh/edit/revert
Wasm. Each phase requested **43,757,384 fewer allocation bytes**. Fresh peak RSS
fell from 367,020 to 325,628 KiB; the retained edit/revert process high-water mark
fell from 494,336 to 402,272 KiB. These memory observations are one paired screen,
not a repeated LLVM RSS measurement or proof of bounded long-session growth.

Release compiler SHA-256:

- Before: `6daefd5ffc0331dc9a7dcd559244657f0350ef019da42244c1c3c4c7bef7140e`
- After: `3acb70294006d14d07475d21b2e111801762ed3107e55e032d22b1398f7714ed`
- Frozen source manifest: `60e11cc0c22ba75b4c5bb892f02a3509d9835a710036874aad360fa09b19a030`

[Archived evidence](measurements/symbolic-journal-2026-10-23.tar.gz) contains the
sanitized complete gate records, seven paired release measurements, earlier
three-pair screen and native allocation/RSS screen. Reproduce the application
comparison with `scripts/bench_compare.ts`; the archived result pins its inputs
and options. The initial gate attempt ran out of disk space before native
execution; the recorded successful gate followed removal of completed build
caches. Its added harness diagnostic preserves child output on assertion failure.

Issue #27 and tasks 100–104 remain open. This result neither meets their latency
and allocation targets nor qualifies the separate in-progress task/channel code.

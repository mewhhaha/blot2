# Continue the Goose K1 rewrite

Worktree: `/home/mewhhaha/.codex/worktrees/0409/blot2`, branch
`rewrite/goose-k1`, based on main `1e39b5d8a4268b9edf769c2813d5231abe1c963b`.
The original main checkout and installed compiler are preserved. The user
authorized the clean rewrite and parallel implementation. Do not close issue
#37 or publish a replacement to main during branch qualification.

All implementation lanes are frozen. The full release gate passed **91 native
entries, 79 Deno tests and the editor gate**, including scalar preconditions,
cache corruption/collision/forged receipts, full output-prefix failures, source
work counters and allocation sweeps. `test-results/qualification.json` identifies
input manifest `5fe240d4ac1b7c08ad609c2444e68cc2a7338e589de479401237fa8d80f6bce6`
and release binary `7b61cff1941de683e99269dc2a3c30cc137201d9bca8f98e90a8d0bbc02366b2`.
The prior ASLR-dependent fault-adapter failure is preserved separately under
`test-results/prior-failures/`; reservation-relative chunks fixed it. Latest
retained sweep:430 initial boundaries,251 subsequent boundaries,all251 rejected
without replacing the previous output.

Read [specification snapshots](docs/spec/INDEX.md), [contracts](docs/CONTRACT.md),
[scope](docs/features.md) and [law ledger](IMPLEMENTATION.md). Goose executable:
`/tmp/blot-k1-goose/build/goose`, pin
`a108677d300cb0e8bbb842c35a353abe67a20c6c`,
`GOOSE_HOME=/tmp/blot-k1-goose-home`. `scripts/bootstrap-goose.sh` recreates it.

Remaining: run I09 paired compile/runtime, retained-edit, near-limit/restart,
runtime telemetry and compiler-iteration measurements sequentially using the
commands in [benchmarks/README.md](benchmarks/README.md). Use output names
`build/bench-k1-release`, `bench-sessions-release`, `bench-limits-release`,
`bench-iteration-debug`, `bench-iteration-release`, and `runtime-telemetry.json`.
The installed paired baseline `/home/mewhhaha/.local/bin/blotc` has SHA-256
`fd2119f5528cb164131e1156d35ba97c434393647f1b326ae5aa154db137d923`, matching
the original checkout's qualified release compiler.

Then run `scripts/package_evidence.py`; publish results and limitations in README,
benchmarks and the final ledger; update this handoff. Do not infer a speedup or
sub-second gdev build from synthetic cases. Keep binaries/caches/intermediates
out of Git. Source changes require a new complete frozen gate before committing.

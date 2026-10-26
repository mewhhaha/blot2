# Goose K1 rewrite handoff

The initial implementation and qualification are complete on `rewrite/goose-k1`,
in `/home/mewhhaha/.codex/worktrees/0409/blot2`. Implementation commit:
`4d5fe60343d1916ec99baa452f2727c48a408f27`. A following documentation/evidence
commit publishes measurements without changing compiler inputs. Main remains at
`1e39b5d8a4268b9edf769c2813d5231abe1c963b`; the installed legacy compiler was
preserved. Do not merge, close issue #37 or replace the installed compiler without
new instructions.

Read [README](README.md), [the stage/law ledger](IMPLEMENTATION.md),
[measurement report](benchmarks/RESULTS.md), [shared contracts](docs/CONTRACT.md)
and [normative snapshots](docs/spec/INDEX.md). The user authorized the clean Goose
rewrite and parallel implementation. All implementation lanes are frozen.

The full release gate passed **91 native entries, 79 Deno tests and editor checks**.
Qualified input manifest:
`5fe240d4ac1b7c08ad609c2444e68cc2a7338e589de479401237fa8d80f6bce6`.
Release executable SHA-256:
`7b61cff1941de683e99269dc2a3c30cc137201d9bca8f98e90a8d0bbc02366b2`.
All 178 qualified input blobs match the implementation commit. The gate includes
scalar input/precondition checks, corrupt optional cache fallback, collision and
forged-receipt controls, every initialized particle prefix, actual Wasm/certificate
validation and complete observed arena-fault sweeps.

[Published evidence](benchmarks/results/k1-initial/manifest.json) contains frozen
gate metadata, raw samples/source/log archive and measurement summaries. No
performance matrices remain running. Do not overwrite or repeat completed runs
without a new implementation, failure or measurement question.

The pinned Goose binary used here is `/tmp/blot-k1-goose/build/goose`, commit
`a108677d300cb0e8bbb842c35a353abe67a20c6c`, with
`GOOSE_HOME=/tmp/blot-k1-goose-home`; `scripts/bootstrap-goose.sh` recreates it.
Compiler changes require a new complete `scripts/check.sh --release` gate.

Measurements show slower paired compilation than legacy in most families.
At 128 callers: fresh session 34.70 ms, unchanged 53.44 ms, body edit 50.42 ms medians.
The 128-depth chain rejects because of its entry wrapper; a 127-depth control passes.
Source checking 65,536 operations takes 58.30 ms; the 65,537th rejects. Compiler rebuilds
still take 37.36 s debug / 57.67 s release (fresh medians); comment-only builds regenerate
identical C but redo both stages. These synthetic cases do not qualify `gdev`.

Follow-up proposals are explicitly unimplemented: function-local affine state and
cached CFG facts in validation; batched layout/canonicalization with reusable
scratch; sparse per-declaration relocation; directly retained immutable Core;
Goose frontend/build-driver iteration work. Profile helper costs before claiming
speedups. Keep required proof/ownership/budget checks, exact interface comparisons,
transaction rollback and independent external-artifact admission.

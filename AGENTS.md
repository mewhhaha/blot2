# Working on the Goose K1 rewrite

This branch implements issue #37 and the normative snapshots in `docs/spec/`.
The user explicitly requested a clean Goose implementation. Legacy coexistence,
legacy default edition, Zig implementation paths and Zig-specific gates are
superseded on this branch. The original compiler remains on `main`.

- Compiler and emitted runtime implementation belong in Goose. Pin the compiler
  revision in `scripts/bootstrap-goose.sh`; do not silently change it.
- Read `docs/CONTRACT.md` before changing shared flat-table contracts.
- Run `scripts/check.sh` before committing compiler changes. An incomplete gate
  or unsupported required feature is not qualification. Report both honestly.
- Keep accepted/rejected semantic laws and executed-Wasm tests. Exercise hostile
  artifacts, ownership failures, budgets and transaction rollback.
- Optional optimization must never determine source admission.
- Preserve unrelated work. Do not install or replace the main compiler with an
  incomplete rewrite. Never commit generated C/binaries as implementation fixes.
- Parallel work is authorized: root owns model, integration, CLI, build and docs;
  frontend owns frontend/proofs; runtime owns runtime/wasm; validator owns
  validate/artifact/hash/optimize. Coordinate contract changes with root.
- Do not file or comment on upstream issues without explicit user approval.

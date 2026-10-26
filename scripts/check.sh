#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--release" ) ]]; then
  printf '%s\n' 'usage: scripts/check.sh [--release]' >&2
  exit 2
fi
export GOOSE
mkdir -p build test-results
"$GOOSE" version
python3 scripts/generate_catalogs.py --check
python3 scripts/generate_artifact_codec.py --check
python3 scripts/generate_relocator.py --check
python3 scripts/generate_canonical_order.py --check
deno run --allow-read --allow-write=test.goose scripts/test_inventory.ts --write
python3 scripts/gate_manifest.py --start "${1:---debug}"
"$GOOSE" run test.goose --include "$PWD/src/platform.h" --debug -q 2>test-results/goose-native-diagnostics.log | tee test-results/native.log
deno run --allow-read scripts/test_inventory.ts --log=test-results/native.log
if [[ "${1:-}" == "--release" ]]; then scripts/build.sh; else scripts/build.sh --debug; fi
npm ci --prefix editor --ignore-scripts --no-audit --no-fund --cache .tools/npm-cache
npm test --prefix editor | tee test-results/editor.log
"${CC:-clang}" -shared -fPIC -O2 tests/arena_fault.c -ldl -o build/arena_fault.so
"${CC:-clang}" -shared -fPIC -O2 tests/publication_fault.c -ldl -o build/publication_fault.so
deno test --allow-read --allow-write --allow-run tests/host_test.ts tests/admission_test.ts tests/concurrency_test.ts tests/optimizer_differential_test.ts tests/inline_test.ts tests/wasm_runtime_test.ts tests/wasm_bridge_test.ts tests/host_bridge_test.ts tests/oom_test.ts tests/wasm_particle_test.ts tests/wasm_closure_test.ts tests/wasm_lifecycle_test.ts tests/wasm_static_test.ts tests/wasm_telemetry_test.ts tests/artifact_cli_test.ts tests/migration_test.ts tests/session_test.ts tests/cancellation_test.ts tests/session_edits_test.ts tests/session_oom_test.ts | tee test-results/deno.log
python3 scripts/gate_manifest.py --finish
# This is the complete current inventory. The implementation ledger separately
# records mandatory specification stages that have not yet been implemented.

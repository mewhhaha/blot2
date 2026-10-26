#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
mkdir -p build
"$GOOSE" version
"$GOOSE" build blot.goose -o build/blot --cc "${CC:-clang}" --standalone --include "$PWD/src/platform.h" -q "$@"

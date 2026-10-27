#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
pin=a108677d300cb0e8bbb842c35a353abe67a20c6c
checkout=.tools/goose
mkdir -p .tools
if [[ ! -d "$checkout/.git" ]]; then
  git clone --filter=blob:none --no-checkout https://github.com/aardappel/goose.git "$checkout"
fi
if [[ $(git -C "$checkout" rev-parse HEAD 2>/dev/null || true) != "$pin" ]]; then
  git -C "$checkout" fetch origin "$pin"
  git -C "$checkout" checkout --detach "$pin"
fi
cmake -S "$checkout" -B "$checkout/build" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="${CC:-clang}" -DCMAKE_CXX_COMPILER="${CXX:-clang++}" -DGOOSE_BUILTIN_LIBS=
cmake --build "$checkout/build" --parallel "${BUILD_JOBS:-2}"
"$checkout/build/goose" version

#!/bin/sh
# Build the Squid compiler written in Goose: compiler-goose/build/squidc-goose.
# Development builds prefer ../goose-to-wasm/build/bin/goosew when present
# (~6s emit, ~48s total). Release builds default to the patched upstream C++
# Goose compiler (faster emitted binary + runtime allocation observer hooks).
# Set GOOSE_USE_UPSTREAM=1 to force upstream Goose, or GOOSE_USE_GOOSEW=1 to
# also use goosew for --release builds.
#   sh compiler-goose/build.sh            debug build
#   sh compiler-goose/build.sh --release  optimized build
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
goose_root=$root/build/goose-port/upstream-d5ae5bb
upstream_goose=$goose_root/build-precision/goose
stdlib=$goose_root/source-precision/stdlib
goosew=$root/../goose-to-wasm/build/bin/goosew

if [ "${1:-}" = "--pgo" ]; then
  if [ ! -x "$upstream_goose" ] || [ ! -s "$upstream_goose" ]; then
    sh "$here/tools/upstream-32a4f44/build.sh"
  fi
  shift
  exec python3 "$here/tools/build_profiled.py" --goose "$upstream_goose" \
    --stdlib "$stdlib" "$@"
fi

is_release=0
for arg in "$@"; do
  if [ "$arg" = "--release" ]; then
    is_release=1
    break
  fi
done

use_goosew=0
if [ "${GOOSE_USE_UPSTREAM:-0}" != "1" ] && [ -x "$goosew" ] && [ -s "$goosew" ]; then
  if [ "$is_release" = "0" ] || [ "${GOOSE_USE_GOOSEW:-0}" = "1" ]; then
    use_goosew=1
  fi
fi

if [ "$use_goosew" = "1" ]; then
  if [ ! -d "$stdlib" ]; then
    sh "$here/tools/upstream-32a4f44/build.sh"
  fi
  exec python3 "$here/build.py" --goose "$goosew" --cc clang \
    --stdlib "$stdlib" --cflag=-Wno-parentheses-equality \
    --stage-timeout 3000 --total-timeout 3400 "$@"
fi

if [ ! -x "$upstream_goose" ] || [ ! -s "$upstream_goose" ]; then
  sh "$here/tools/upstream-32a4f44/build.sh"
fi
exec python3 "$here/build.py" --goose "$upstream_goose" --cc clang \
  --stdlib "$stdlib" \
  --stage-timeout 3000 --total-timeout 3400 "$@"

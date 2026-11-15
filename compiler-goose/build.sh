#!/bin/sh
# Build the Blot compiler written in Goose: compiler-goose/build/blotc-goose.
# The first run also builds the patched Goose compiler it needs (about two
# minutes; clang, cmake and ninja must be installed).
#   sh compiler-goose/build.sh            debug build, about a minute
#   sh compiler-goose/build.sh --release  optimized build, about four minutes
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
goose_root=$root/build/goose-port/upstream-d5ae5bb
goose=$goose_root/build-precision/goose
if [ ! -x "$goose" ] || [ ! -s "$goose" ]; then
  sh "$here/tools/upstream-32a4f44/build.sh"
fi
exec python3 "$here/build.py" --goose "$goose" --cc clang \
  --stdlib "$goose_root/source-precision/stdlib" \
  --stage-timeout 3000 --total-timeout 3400 "$@"

#!/bin/sh
# Build the private Goose checker: upstream Goose at $GOOSE_UPSTREAM plus every
# patch in ./series (01-17), into build/goose-port/upstream-<short>/build-precision.
# The series was ported against 32a4f44; d5ae5bb adds only a stdlib change.
# Run under the heavy-job lock:
#   flock /var/tmp/blot2-heavy.lock systemd-run --user --scope -q \
#     -p MemoryMax=14G -p MemorySwapMax=2G sh compiler-goose/tools/upstream-32a4f44/build.sh
set -eu
upstream=${GOOSE_UPSTREAM:-d5ae5bbda990923fa4129f969c7f853c20d4d1e6}
short=$(printf %.7s "$upstream")
tools=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$tools/../../.." && pwd)
work=$root/build/goose-port/upstream-$short
src=$work/source-precision
out=$work/build-precision
mkdir -p "$work"
if [ ! -d "$work/source" ]; then
  mkdir -p "$work/source"
  curl -sSL "https://codeload.github.com/aardappel/goose/tar.gz/$upstream" |
    tar -xz -C "$work/source" --strip-components=1
fi
rm -rf "$src" && cp -r "$work/source" "$src"
grep -v '^#' "$tools/series" | while read -r patch; do
  patch -p1 --fuzz=0 -s -d "$src" -i "$tools/$patch"
done
mkdir -p "$out"
start=$(date +%s)
cmake -S "$src" -B "$out" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
  "-DCMAKE_CXX_FLAGS=-gline-tables-only -DGOOSE_EXPANSION_NODE_LIMIT=1000000 -DGOOSE_REACHABLE_PROGRAM=1" \
  "-DGOOSE_VERSION=$short-precision" > "$out/configure.log" 2>&1
ninja -C "$out" -j 8 goose > "$out/build.log" 2>&1
echo "$short-precision $(sha256sum "$out/goose" | cut -d' ' -f1) $(( $(date +%s) - start ))s" | tee "$out/receipt.txt"

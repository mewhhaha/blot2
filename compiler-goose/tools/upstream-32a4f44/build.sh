#!/bin/sh
# Build the private Goose checker: upstream Goose at $GOOSE_UPSTREAM plus every
# patch in ./series (01-29), into build/goose-port/upstream-<short>/build-precision.
# GOOSE_PGO=1 also trains on compiler-goose and builds with that profile (same output).
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
flags="-gline-tables-only -DGOOSE_EXPANSION_NODE_LIMIT=1000000 -DGOOSE_REACHABLE_PROGRAM=1"
configure() { # <build dir> <extra C++ flags> <extra link flags>
  cmake -S "$src" -B "$1" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    "-DCMAKE_CXX_FLAGS=$flags $2" "-DCMAKE_EXE_LINKER_FLAGS=$3" \
    "-DGOOSE_VERSION=$short-precision" > "$1/configure.log" 2>&1
}
profile=""
if [ -n "${GOOSE_PGO:-}" ]; then
  # Profile-guided build: an instrumented checker emits compiler-goose once
  # (the real workload, about as long as one build.py emit), and the
  # release build is optimized for that profile. Output is unchanged.
  gen=$work/build-precision-pgo-gen
  rm -rf "$gen" && mkdir -p "$gen/profile" "$gen/train"
  configure "$gen" -fprofile-instr-generate -fprofile-instr-generate
  ninja -C "$gen" -j 8 goose > "$gen/build.log" 2>&1
  LLVM_PROFILE_FILE="$gen/profile/goose-%p.profraw" "$gen/goose" -o "$gen/train/out.c" \
    --header "$gen/train/out.h" -O0 --stdlib "$src/stdlib" "$root/compiler-goose/src/main.goose" \
    > "$gen/train/log.txt" 2>&1
  llvm-profdata merge -o "$out/goose.profdata" "$gen"/profile/*.profraw
  profile="-fprofile-instr-use=$out/goose.profdata -Wno-backend-plugin"
fi
configure "$out" "$profile" ""
ninja -C "$out" -j 8 goose > "$out/build.log" 2>&1
echo "$short-precision $(sha256sum "$out/goose" | cut -d' ' -f1) $(( $(date +%s) - start ))s" | tee "$out/receipt.txt"

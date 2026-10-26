#!/bin/sh
# Offline known vectors and a differential check against Zig 0.17.0.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
: "${GOOSE:=goose}"
: "${ZIG:=zig}"
: "${GOOSE_HOME:=$script_dir/build/goose-home}"
export GOOSE_HOME
version=$("$ZIG" version)
case "$version" in 0.17.0|0.17.0-*) ;; *) echo "Zig 0.17.0 required, got $version" >&2; exit 1 ;; esac
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
"$ZIG" run -fno-llvm -fno-lld "$script_dir/blake3_oracle.zig" 2> "$scratch/oracle"
for level in 0 2; do
    "$GOOSE" --debug "-O$level" "$script_dir/blake3_test.goose"
    "$GOOSE" --debug "-O$level" "$script_dir/blake3_diff.goose" > "$scratch/goose"
    diff -u "$scratch/oracle" "$scratch/goose"
done
echo 'BLAKE3 offline differential passed'

#!/bin/sh
# Build the experimental compiler with the pinned Goose toolchain (see README).
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
: "${GOOSE:=goose}"
: "${GOOSE_HOME:=$script_dir/build/goose-home}"
export GOOSE_HOME
mkdir -p "$script_dir/build"
"$GOOSE" build -o "$script_dir/build/blot-k1" "$script_dir/main.goose"

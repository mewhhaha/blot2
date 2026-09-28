#!/usr/bin/env bash
# Compile the original Bend sources through the release CLI's ES-module emitter.
# Sequential generation avoids running three memory-heavy JS loaders together.
set -euo pipefail
cd "$(dirname "$0")/../.."
bend version
mkdir -p generated/compiler
for pair in main:compiler native_session:native_session native_output:native_output; do
  source="${pair%%:*}"
  target="${pair##*:}"
  /usr/bin/time -v bend "compiler/$source.bend" -o "generated/compiler/$target.tmp.mjs"
  test -s "generated/compiler/$target.tmp.mjs"
  mv "generated/compiler/$target.tmp.mjs" "generated/compiler/$target.js"
done

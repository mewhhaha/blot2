#!/usr/bin/env bash
# Source from project root.
GOOSE="${GOOSE:-$PWD/.tools/goose/build/goose}"
export GOOSE_HOME="${GOOSE_HOME:-$PWD/.goose}"
if [[ ! -x "$GOOSE" ]]; then
  printf '%s\n' 'Missing Goose; run scripts/bootstrap-goose.sh or set GOOSE.' >&2
  exit 1
fi
version=$("$GOOSE" version)
if [[ "$version" != *a108677* ]]; then
  printf 'Wrong Goose revision: %s\n' "$version" >&2
  exit 1
fi

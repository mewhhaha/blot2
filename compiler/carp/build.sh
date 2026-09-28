#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${CARP_DIR:?Set CARP_DIR to the pinned Carp checkout (see compiler/carp/README.md)}"
CARP="${CARP:-carp}"
case "${1:-debug}" in
  debug) "$CARP" -b compiler/carp/main.carp ;;
  release) "$CARP" --optimize -b compiler/carp/main.carp ;;
  sanitize)
    "$CARP" --eval-postload '(add-cflag "-fsanitize=address,undefined") (add-cflag "-fno-omit-frame-pointer")' -b compiler/carp/main.carp ;;
  *) echo 'Usage: bash compiler/carp/build.sh [debug|release|sanitize]' >&2; exit 2 ;;
esac
test -x generated/carp/blotc-carp

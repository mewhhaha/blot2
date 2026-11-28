#!/bin/sh
# Build the Squid compiler written in Goose: compiler-goose/build/squidc-goose.
# All builds (dev, --release, --pgo) default to goosew (mewhhaha/goose-to-wasm):
#   1. $GOOSEW_BIN if set
#   2. ../goose-to-wasm/build/bin/goosew (sibling checkout)
#   3. goosew on PATH
#   4. Auto-fetched pinned release in compiler-goose/build/goosew/<version>/
# Set GOOSE_USE_UPSTREAM=1 only to opt into the legacy patched C++ Goose build.
#   sh compiler-goose/build.sh            debug build
#   sh compiler-goose/build.sh --release  optimized build
#   sh compiler-goose/build.sh --pgo      profile-guided optimized build
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
cc=${CC:-clang}
goosew_version=${GOOSEW_VERSION:-v2026.4-8}

verify_sha256() {
  file=$1
  expected=$2
  if [ -z "$expected" ]; then
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$file" | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$file" | awk '{print $1}')
  else
    actual=$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$file")
  fi
  if [ "$actual" != "$expected" ]; then
    echo "build.sh: SHA-256 mismatch for $file: got $actual, expected $expected" >&2
    exit 1
  fi
}

fetch_goosew() {
  cache_dir=$here/build/goosew/$goosew_version
  cached_bin=$cache_dir/bin/goosew
  if [ -x "$cached_bin" ] && [ -s "$cached_bin" ] && [ -d "$cache_dir/bin/stdlib" ]; then
    printf '%s\n' "$cached_bin"
    return 0
  fi

  os=$(uname -s)
  arch=$(uname -m)
  asset=""
  expected_sha=""
  case "$os:$arch" in
    Linux:x86_64|Linux:amd64)
      asset="goose-to-wasm-${goosew_version}-linux-x64.tar.gz"
      if [ "$goosew_version" = "v2026.4-8" ]; then
        expected_sha="a5c2da03870c8f602525d3031feb4f523bd4c391334816870cca4e78e570cd09"
      fi
      ;;
    Darwin:arm64|Darwin:aarch64)
      asset="goose-to-wasm-${goosew_version}-macos-arm64.tar.gz"
      if [ "$goosew_version" = "v2026.4-8" ]; then
        expected_sha="57e7f7013e6358764d07dbc1aa847e36ec3fd60bd00eac16fe03e7c35ec61925"
      fi
      ;;
    Darwin:x86_64)
      asset="goose-to-wasm-${goosew_version}-macos-x64.tar.gz"
      if [ "$goosew_version" = "v2026.4-8" ]; then
        expected_sha="3281bd192c457ab63497fbca78104fcb75c3c4854bc25593676bb58d952fe57c"
      fi
      ;;
  esac

  mkdir -p "$here/build/goosew"
  tmp_dir=$(mktemp -d "$here/build/goosew/.fetch.XXXXXX")
  trap 'rm -rf "$tmp_dir"' EXIT INT TERM

  if [ -n "$asset" ]; then
    url="https://github.com/mewhhaha/goose-to-wasm/releases/download/${goosew_version}/${asset}"
    echo "build.sh: fetching goosew ${goosew_version} from ${url}" >&2
    curl --fail --silent --show-error --location --retry 3 "$url" -o "$tmp_dir/$asset"
    verify_sha256 "$tmp_dir/$asset" "$expected_sha"
    mkdir -p "$tmp_dir/out"
    tar -xzf "$tmp_dir/$asset" --strip-components=1 -C "$tmp_dir/out"
    rm -rf "$cache_dir"
    mv "$tmp_dir/out" "$cache_dir"
  else
    # Source bootstrap for platforms without a prebuilt release tarball (e.g. Linux arm64).
    src_url="https://codeload.github.com/mewhhaha/goose-to-wasm/tar.gz/refs/tags/${goosew_version}"
    echo "build.sh: bootstrapping goosew ${goosew_version} for ${os}/${arch} from ${src_url}" >&2
    mkdir -p "$tmp_dir/src"
    curl --fail --silent --show-error --location --retry 3 "$src_url" \
      | tar -xz --strip-components=1 -C "$tmp_dir/src"
    python3 "$tmp_dir/src/scripts/bootstrap.py" --build-dir "$tmp_dir/out" --cc "$cc" >&2
    rm -rf "$cache_dir"
    mv "$tmp_dir/out" "$cache_dir"
  fi

  rm -rf "$tmp_dir"
  trap - EXIT INT TERM
  printf '%s\n' "$cached_bin"
}

resolve_goosew() {
  if [ -n "${GOOSEW_BIN:-}" ] && [ -x "$GOOSEW_BIN" ] && [ -s "$GOOSEW_BIN" ]; then
    printf '%s\n' "$GOOSEW_BIN"
    return 0
  fi
  sibling=$root/../goose-to-wasm/build/bin/goosew
  if [ -x "$sibling" ] && [ -s "$sibling" ]; then
    printf '%s\n' "$sibling"
    return 0
  fi
  if command -v goosew >/dev/null 2>&1; then
    command -v goosew
    return 0
  fi
  fetch_goosew
}

resolve_stdlib() {
  bin=$1
  if [ -n "${GOOSE_STDLIB:-}" ] && [ -d "$GOOSE_STDLIB" ]; then
    printf '%s\n' "$GOOSE_STDLIB"
    return 0
  fi
  bin_dir=$(cd "$(dirname "$bin")" && pwd)
  for candidate in \
    "$bin_dir/stdlib" \
    "$bin_dir/../stdlib" \
    "$root/../goose-to-wasm/build/bin/stdlib" \
    "$root/../goose-to-wasm/stdlib"; do
    if [ -d "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  echo "build.sh: could not find Goose stdlib for $bin (set GOOSE_STDLIB)" >&2
  exit 1
}

if [ "${GOOSE_USE_UPSTREAM:-0}" = "1" ]; then
  goose_root=$root/build/goose-port/upstream-d5ae5bb
  goose_bin=$goose_root/build-precision/goose
  stdlib=$goose_root/source-precision/stdlib
  if [ ! -x "$goose_bin" ] || [ ! -s "$goose_bin" ]; then
    sh "$here/tools/upstream-32a4f44/build.sh"
  fi
else
  goose_bin=$(resolve_goosew)
  stdlib=$(resolve_stdlib "$goose_bin")
fi

if [ "${1:-}" = "--pgo" ]; then
  shift
  exec python3 "$here/tools/build_profiled.py" --goose "$goose_bin" \
    --stdlib "$stdlib" "$@"
fi

exec python3 "$here/build.py" --goose "$goose_bin" --cc "$cc" \
  --stdlib "$stdlib" --stage-timeout 3000 --total-timeout 3400 "$@"

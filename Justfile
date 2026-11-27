# Build the optimized compiler and its package payload.
build:
  deno task package:build

# Build the debug compiler during compiler development.
dev:
  deno task build:compiler:dev

check:
  deno task check

test:
  deno task test

guide:
  deno task squid guide

compile source="examples/prelude.sq" output="build/example.wasm":
  deno task squid build {{quote(source)}} {{quote(output)}}

fmt source:
  deno task squid fmt {{quote(source)}}

install:
  deno task helix:install

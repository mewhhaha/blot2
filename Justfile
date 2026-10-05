# Build the Zig compiler and its package payload.
build:
  deno task package:build

# Incrementally rebuild Zig during compiler development.
dev:
  deno task build:compiler:dev

check:
  deno task check

test:
  deno task test

guide:
  deno task blot guide

compile source="examples/prelude.blot" output="build/example.wasm":
  deno task blot build {{quote(source)}} {{quote(output)}}

fmt source:
  deno task blot fmt {{quote(source)}}

install:
  deno task helix:install

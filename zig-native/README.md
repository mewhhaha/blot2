# Zig compiler

Blot's only compiler lives here. Zig owns lexing, parsing, type/effect inference,
staging, retained revisions and WebAssembly emission. Deno supplies the
[host tools](../compiler/README.md).

The owned-storage rewrite is unfinished. Read [CONTINUE.md](../CONTINUE.md),
[AGENTS.md](../AGENTS.md) and [the active task index](../tasks/STORAGE_REWRITE.md).
The next milestone is a real Gdev frame in Pen; older test counts and benchmark
reports do not qualify it. This is greenfield work: remove superseded code and
APIs rather than adding compatibility layers.

## Build

Use Zig **0.17.0**. From the repository root:

```sh
zig version
deno task build:compiler:dev
```

Development uses the native backend (`-Dllvm=false`) and installs
`zig-out-dev/bin/blotc`. For a direct build in this directory:

```sh
zig build install compiler-identity -Doptimize=safe -Dllvm=false --prefix zig-out-dev
```

Keep the executable and sibling `std/` from the same checkout. See the handoff
for the tracked real-Gdev compilation and one-frame runners.

## Validation

Run coherent affected laws during integration. The documented development
family is `deno task check:dev --area static-sharing`; list available families
with `deno task check:dev --list-areas`. It is not full qualification.

Final compiler changes require `deno task test:compiler` and Zig lint as
specified in `AGENTS.md`. Native unit-test compilation always uses the native
backend, including the full gate. LLVM is reserved for the final release
compiler and release measurements. Compiled inventories and executed tests must
be reported separately.

## Contracts and evidence

- [Compiler ownership contract](CONTRACT.md).
- [Scoped storage](SCOPED_STORAGE.md) and [rewrite decisions](STORAGE_REWRITE_REVIEW.md).
- [Source areas](SOURCE_AREAS.md) and [architecture](ARCHITECTURE.md).
- [Project client](PROJECT_CLIENT.md), [project protocol](PROJECT_PROTOCOL.md),
  and [guest ABI](../compiler/guest-abi.md).
- [Current status](STATUS.md) and [documentation map and historical evidence](../docs/README.md).

Legacy-backend retirement remains task 120; its presence in the source is
unfinished migration work, not a backward-compatibility promise.

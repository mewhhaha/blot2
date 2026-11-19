# The Blot compiler

This is Blot's compiler. It is written in Goose and was ported from a
compiler written in Zig, which was removed on 15 November 2026 once the two
matched. [tasks/GOOSE_PORT.md](../tasks/GOOSE_PORT.md) has the record of the
port: the comparison, what went with Zig, the known differences and the
speed.

## Layout

- `src/` is the compiler: the parser, the checker, Core lowering, the
  direct backend (`src/direct/`), the project pipeline, the project server
  and the command line (`src/driver/`). The module map follows the Zig
  source it came from; `source-correspondence.json` names the Zig file of
  each module.
- `native/` contains the entry point, file and process calls, the shared
  Linux checker queue in `check_queue.c`, and the pool allocation observer.
- `tools/` has the generators for the generated modules in `src/support/`
  and `src/reuse/`, the two models they read, the build of the patched
  Goose, and the test runners.
- `tests/` has the recorded references and the laws.

## Build

From the repository root:

- `deno task build:compiler` writes the optimized compiler,
  `compiler-goose/build/blotc-goose`, in about seven minutes. Pen, the
  sibling checkouts and the tests' default path run this file.
- `deno task build:compiler:dev` writes a debug compiler,
  `compiler-goose/build/blotc-goose-dev`, in about a minute and a half.

Both run `compiler-goose/build.sh`, which takes `--release`, `--output FILE`
and `--cflag=FLAG`. It needs clang, cmake, ninja and Python 3. A rebuilt
compiler has a new identity, so dependency bundles made by the previous
build are declined as stale.

- The first run builds the Goose compiler: upstream Goose
  ([github.com/aardappel/goose](https://github.com/aardappel/goose)) with
  the patch series in `tools/upstream-32a4f44/`, into
  `build/goose-port/upstream-d5ae5bb/build-precision/` (about two minutes).
- Then `build.py` has Goose emit C and compiles it with clang. It
  regenerates `src/source_identity.goose`.

After a module, a struct or a field is added or removed, regenerate the
adapters before building:

```bash
python3 compiler-goose/tools/write_structural_adapters.py
python3 compiler-goose/tools/write_json_adapters.py
python3 compiler-goose/tools/write_project_packet.py
python3 compiler-goose/tools/write_project_packet_contexts.py
python3 compiler-goose/tools/write_dependency_codecs.py
python3 compiler-goose/tools/write_dependency_owned_headers.py
```

Two of them read a model that is edited by hand:

- `tools/dependency-wire-model.json` declares the format of dependency
  bundles: each type on the wire, its fields in wire order, and the fields
  of the Goose type that stay off the wire (`unwired`). When a Goose type
  on the wire gains or loses a field or a variant, `write_dependency_codecs.py`
  stops and names it; add it to the model.
- `tools/json-union-model.json` gives, for 15 enums, the payload type each
  variant had in Zig. It decides whether a variant's payload is written
  bare or as an object in JSON. An enum that is not listed writes objects.

## Tests

- `deno task test:compiler` runs the tooling tests, the optimized build, the
  three reference suites, packaging and all guest and host tests. Current
  results are in [the handoff](../CONTINUE.md). `deno task test:guest` runs
  the guest and host suite against the existing optimized compiler, and
  `deno task test:compiler:dev FILES` builds the debug compiler and runs
  those files.
- The reference suites began with the Zig compiler's output on 15 November
  2026. They also cover programs and deliberate output changes added since.
  - `python3 compiler-goose/tools/test_fixtures.py` builds each program in
    `tests/fixtures/` and checks its exit code, Wasm and result records.
  - `python3 compiler-goose/tools/test_uniqueness.py` requires the recorded
    lowering diagnostics for the 212 programs of `tests/uniqueness/`. The
    139 named `e…` to `n…` are about `own` parameters, moves at a local's
    last read, the rules for every function, what stays while `=` exists
    (`lent`, kept values, function values), `own` in function types,
    taking a value apart, names that borrow, borrowed values without a
    name, fields given to an `own` parameter, values whose type is
    not known yet, views lent, fields that leave in a result and arms
    that move a local,
    which Zig never had; their record is this compiler's, read
    through by hand. Five of Zig's 73 (`b25`, `b41`, `c05`, `c10`, `c07`) are
    accepted now, the first four because the value they alias moves (in
    `b25` out of an arm of an `if`) and
    `c07` because rows a loop walked are the array's own again after it;
    `b18` and one site of `c22` because they take a fresh tuple apart,
    and two sites of `b44` because a name borrows one field only.
  - `python3 compiler-goose/tools/test_direct.py` runs each law of
    `tests/direct/` and requires the recorded bytes.

  After a deliberate change of behavior, `--record EXE` rewrites the first
  two from that compiler.
- `tests/checker_tools`, `tests/copied_argument_contents` and
  `tests/global_empty_facts` test the patches to the Goose compiler, not
  this compiler.

## Checking published types

`build/blotc-goose check-exports FILE...` checks public value signatures from
source declarations. Add `--include-private` before the file paths to check
every module-level value. Each file produces a JSON summary with the number of
checked declarations and missing signatures. A missing signature exits with
status 1. Run the normal project build to check bodies and imported types.

## Finding a pooled owner that is not released

The `memory` field of a compilation record counts the compiler's pooled
owners; `live_bytes` must be 0. When it is not, build with debug
information (`sh compiler-goose/build.sh --cflag=-g`) and trace the pool
events under gdb: break on `event` in native/allocation_observer.c, sum
allocated minus freed bytes for each `owner` after
`blot_allocation_observer_mark`, and match the owner that keeps bytes
against the `base` of each `gs_rhdr` field of `gs_globals_main`. The field
name is the pool; the callers of its allocations name the site.

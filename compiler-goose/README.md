# The Blot compiler in Goose

This is the port of `../compiler/` (Zig) that is meant to replace it. The
state, the steps and the measurements are in
[tasks/GOOSE_PORT.md](../tasks/GOOSE_PORT.md).

## Layout

- `src/` is the compiler: the parser, the checker, Core lowering, the
  direct backend (`src/direct/`), the project pipeline, the project server
  and the command line (`src/driver/`). It has every command of `blotc`.
  The module map follows the Zig source; a module keeps the name of its
  Zig original.
- `pending/` holds three modules that Zig uses only from its tests, and 13
  laws written for the 12 November interfaces. Nothing builds or runs
  them.
- `native/` is the C host: the entry point, file and process calls, and
  the observer that counts pool requests for the `memory` record.
- `tools/` has the generators for the generated modules in `src/support/`
  and `src/reuse/`, the build of the patched Goose, and the test runners.

## Build

`sh compiler-goose/build.sh` (`deno task build:goose:dev`) writes
`compiler-goose/build/blotc-goose` (debug, about a minute and a half);
`--release` (`deno task build:goose`) optimizes it (about seven minutes). It needs clang, cmake, ninja and Python 3. A rebuilt compiler
has a new identity, so dependency bundles made by the previous build are
declined as stale.

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

## Tests

- The guest and host suite takes the compiler as its argument:
  `deno task test:goose` runs it against `compiler-goose/build/blotc-goose`
  (1,054 pass, 101 ignored, as for Zig).
- `python3 compiler-goose/tools/test_direct.py` runs each law in
  `tests/direct/` against the Zig source of the direct backend and requires
  the same bytes.
- `python3 compiler-goose/tools/test_uniqueness.py --zig compiler/zig-out/bin/blotc`
  builds each program in `tests/uniqueness/` with both compilers and
  requires the same lowering diagnostics.
- `tests/checker_tools`, `tests/copied_argument_contents`,
  `tests/global_empty_facts` and `tests/qualification` test the patches to
  the Goose compiler, not this port.

## Finding a pooled owner that is not released

The `memory` field of a compilation record counts the compiler's pooled
owners; `live_bytes` must be 0. When it is not, build with debug
information (`sh compiler-goose/build.sh --cflag=-g`) and trace the pool
events under gdb: break on `event` in native/allocation_observer.c, sum
allocated minus freed bytes for each `owner` after
`blot_allocation_observer_mark`, and match the owner that keeps bytes
against the `base` of each `gs_rhdr` field of `gs_globals_main`. The field
name is the pool; the callers of its allocations name the site.

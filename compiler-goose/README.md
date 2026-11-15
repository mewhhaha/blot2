# The Blot compiler in Goose

This is the port of `../compiler/` (Zig) that is meant to replace it. The
state, the steps and the measurements are in
[tasks/GOOSE_PORT.md](../tasks/GOOSE_PORT.md).

## Layout

- `src/` is what builds today: the parser, the checker, Core lowering and a
  command line with `lex`, `parse`, `check` and `build` for one file. The
  module map follows the Zig source; a module keeps the name of its Zig
  original.
- `src/direct/` is the direct backend. `writer` and `runtime` are ported
  and produce the same bytes as Zig.
- `pending/` holds modules that are ported but not yet brought up to
  today's Zig source: the project server, dependency bundles, editor
  completion and native assets, with their laws in `pending/tests/`. They
  are outside `src/` so the build does not load them.
- `native/` is the C host: the entry point, file and process calls.
- `tools/` has the generators for the generated modules in `src/support/`
  and `src/reuse/`, the build of the patched Goose, and the test runners.

## Build

1. The Goose compiler:
   `sh compiler-goose/tools/upstream-32a4f44/build.sh` builds upstream
   Goose ([github.com/aardappel/goose](https://github.com/aardappel/goose))
   with the patch series beside it into
   `build/goose-port/upstream-d5ae5bb/build-precision/`.
2. The Blot compiler:
   `python3 compiler-goose/build.py --goose build/goose-port/upstream-d5ae5bb/build-precision/goose --cc clang --stdlib build/goose-port/upstream-d5ae5bb/source-precision/stdlib --stage-timeout 1500 --total-timeout 2400`
   writes `compiler-goose/build/blotc-goose`. `--release` selects `-O2`.
   The build regenerates `src/source_identity.goose`.

After a module, a struct or a field is added or removed, regenerate the
adapters before building:

```bash
python3 compiler-goose/tools/write_structural_adapters.py
python3 compiler-goose/tools/write_json_adapters.py
python3 compiler-goose/tools/write_project_packet.py
python3 compiler-goose/tools/write_project_packet_contexts.py
```

## Tests

- `python3 compiler-goose/tools/test_direct.py` runs each law in
  `tests/direct/` against the Zig source of the direct backend and requires
  the same bytes.
- `python3 compiler-goose/tools/test_uniqueness.py --zig compiler/zig-out/bin/blotc`
  builds each program in `tests/uniqueness/` with both compilers and
  requires the same lowering diagnostics.
- `tests/checker_tools`, `tests/copied_argument_contents`,
  `tests/global_empty_facts` and `tests/qualification` test the patches to
  the Goose compiler, not this port.

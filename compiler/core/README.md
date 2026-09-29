# Native typed compiler core

Experimental compiler on PR #7. The ordinary Bend compiler is not replaced. The
native path uses the existing parser and host protocol, with compact Unicode
storage, exact semantic IDs, native persistent indexes, and worker-local caches.
The source migration bridge preserves existing inference and specialization
algorithms while their replacement is developed; this is not the complete
level-based, typed-instance redesign yet.

## Build and run

Requires a 64-bit OCaml 5 installation, a C toolchain, and Python 3:

```sh
make -C compiler/core
```

For the source CLI (Deno is also required), use the explicit core tasks:

```sh
deno task build:compiler:core
deno task blot:core check examples/generic_effects.blot
deno task blot:core build examples/scalar.blot build/scalar.wasm
deno task test:compiler:core
```

These tasks do not install or overwrite the default compiler. `blot:core` uses
only the core executable; a missing executable is an error, not a fallback. The
ordinary source grammar, diagnostics, formatting and guide are shared with the
existing CLI. The core task tests do not require Bend or a JavaScript compiler
backend; the full differential suites below separately require their oracle.

The executable is `compiler/core/_build/blotc`. Build output includes generated
semantic source and `build-manifest.json` with input and executable hashes.
Unchanged builds do not recompile or relink; changed modules and their
transitive consumers are rebuilt. The final executable is replaced atomically.
The executable needs neither Python nor Bend to run.

Existing `createNativeCompiler` and incremental/project factories select it
using `{ executable: new URL('./core/_build/blotc', import.meta.url) }` from a
file under `compiler/`. No silent fallback to another compiler is installed.

```sh
# Deno and the generated parser are needed for host smoke tests.
make -C compiler/core test
# Also build the unchanged Bend JS reference for differential checks.
python3 scripts/build_compiler_reference.py
make -C compiler/core parity
```

The full redesign remains a draft. Checkpoint artifacts contain committed
source, build provenance, generated native modules, executables, and test logs.
The recovered source has been revalidated; results for each newer checkpoint
remain bound to its own executable hash and attached logs. See RECOVERY.md for
the publication history and [PROGRESS.md](PROGRESS.md) for the latest verified
implementation boundary.

## Checkpoints

```sh
make -C compiler/core test-build test-no-reference
python3 compiler/core/checkpoint.py --output build/core-checkpoint.zip \
  --base <previous-commit> --evidence build/core-parity.json
```

Checkpointing rejects uncommitted changes, modified inputs, changed generated
modules, or an executable that differs from its manifest. The incremental Git
bundle can be fetched into another checkout; generated sources and a Linux
executable are packaged separately from version-controlled source. Native builds
in one checkout are serialized to protect temporary products and manifests.

The Native typed core workflow tests the actual native executable, including a
clean source compilation without any JavaScript compiler files. Its differential
suite separately builds the pinned, unchanged Bend oracle. The Core checkpoint
workflow continues to save source on each push independently of validation.

## New inference kernel

`Core_levels` implements task-local type-variable links, rollback-safe path
compression, lexical levels, multiplicity-preserving effect rows and immutable
DAG schemes. It is a tested migration component, not yet a replacement for the
source compiler's existing inference algorithm. See
[TYPE_GRAPH.md](TYPE_GRAPH.md).

The explicit `--verify-type-graph` migration gate also checks constraints from
real source and native session compilation against the new graph. It leaves
production results and diagnostics with the compatibility solver and fails on a
disagreement. The native checkpoint workflow runs both the ordinary suite and
this verification suite and retains their separate reports.

A checkpoint also carries the raw Git commit object. Packaging holds the same
lock as the builder and verifies build inputs against the committed archive.
`test_checkpoint.py` verifies its archive, restores the exact tree/commit (and
fast-forwards its bundle when present), runs the saved executable, and rejects
modified build inputs, generated sources, executables and uncommitted source
changes.

```sh
python3 compiler/core/test_checkpoint.py /path/to/checkpoint.zip
# Also verify restoration without any existing Git base:
python3 compiler/core/test_checkpoint.py /path/to/checkpoint.zip --source-only
```

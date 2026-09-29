# Native typed compiler core

Experimental compiler on PR #7. The ordinary Bend compiler is not replaced.
The native path uses the existing parser and host protocol, with compact Unicode
storage, exact semantic IDs, native persistent indexes, and worker-local caches.
The source migration bridge preserves existing inference and specialization
algorithms while their replacement is developed; this is not the complete
level-based, typed-instance redesign yet.

## Build and run

Requires a 64-bit OCaml 5 installation, a C toolchain, and Python 3:

```sh
make -C compiler/core
```

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

The full redesign remains a draft. Checkpoint artifacts contain committed source,
build provenance, generated native modules, executables, and test logs. The
recovered source is being revalidated; earlier local test totals do not certify
a different recovered build. See RECOVERY.md for the publication history.

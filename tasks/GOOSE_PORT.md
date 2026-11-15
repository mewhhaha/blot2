# Finish the Goose compiler and retire Zig

The owner's direction (15 November 2026): "add some more patches to goose
to make it faster until goose to wasm is ready. And try to finish the goose
compiler so we can retire zig."

This replaces the 14 November choice to build the port with plain upstream
Goose only. The patch series is back in
compiler-goose/tools/upstream-32a4f44/.

## Where the port stands

- **What it is.** compiler-goose/ ports the scoped compiler as the Zig
  source stood at 44ee94f4 (12 November): 551 files, 125,000 lines.
- **It built and matched Zig** on 12 and 13 November, with the patched
  Goose:
  - a whole executable
    ([record](../benchmarks/evidence/qualification/2026-11-12-goose-first-executable.json));
  - Ink's suite with the same outcome on all 73 modules
    ([record](../benchmarks/evidence/qualification/2026-11-12-goose-ink-parity.json));
  - Gdev Main to the same bytes as Zig, with an identical first frame.
- **It was slower than Zig**
  ([record](../benchmarks/evidence/measurements/2026-11-13-goose-compile-speed.json)).
  Seconds to compile, all with byte-identical Wasm:

  | Program | Zig, LLVM release | Goose, release |
  | --- | ---: | ---: |
  | Ink app-words | 0.1 | 1.4 |
  | Ink next-improvements | 0.5 | 4.1 |
  | Ink six-more-physics | 5.4 | 16.2 |
  | Gdev Main | 6.9 | 204.0 |

- **It builds again** (15 November, cloud container, 4 cores, 15 GiB):
  - `sh compiler-goose/tools/upstream-32a4f44/build.sh` builds upstream
    Goose d5ae5bb with patches 01–29 in 136 s.
  - That Goose checks the port without an error in 271 s at 10.4 GiB.
  - `compiler-goose/build.py` emits 229 MB of C (387 s of CPU) and links
    `compiler-goose/build/blotc-goose` (clang -O0, 86 s). It compiles a
    one-line program.
- **It cannot read today's sources.** The Zig compiler moved on after the
  port's last sync: the direct backend replaced the scoped one, and memory
  model phase 1 added the store `place = value`. The port stops at the
  first `=` in std/prelude.blot with a syntax error.
- **Stale notes.** compiler-goose/README.md, compiler-goose/CONTINUE.md and
  source-correspondence.json still say no executable exists. They predate
  12 November.

## What retiring Zig takes

In this order, so an executable keeps working throughout:

1. **Port the direct backend** (compiler/src/direct/ and compile.zig,
   6,487 lines) into compiler-goose/src/direct/, beside the scoped
   backend: writer, types, runtime, emit, function, direct.
2. **Bring the frontend up to date.** Outside the backends the Zig source
   changed little since 44ee94f4:
   - the parser's `store_stmt` and `place`;
   - check.zig (+305, −770 lines), core_builder.zig (+71, −32), the store
     flag on Core updates;
   - the new uniqueness pass (871 lines);
   - the checker modules that moved from backend/ to check/, which the port
     still has under src/backend/;
   - 15 November's checker changes (associated members imported on first
     lookup, rebinding without generalization).
3. **Match Zig** on compiler/fixtures/direct, the guest suite (it takes
   the compiler as an argument), Ink's suite through Pen and the Gdev
   frame.
4. **Delete the scoped compiler from the port**: src/backend, src/eval,
   src/runtime and the scoped part of src/reuse, about 52,000 lines whose
   Zig originals are gone. The project server builds each revision fresh,
   as in Zig.
5. **Decide on speed.** At the last measurement the Goose compiler was 3 to
   30 times slower than the Zig release build. The owner's goal is faster
   compiles, so retiring Zig waits on this number for the new backend.

## Making Goose faster

Building the port is one Goose run of about 6.5 minutes of CPU, plus the C
compile. Where the time goes (133 stack samples of the emit, 15 November):

| Where | Share |
| --- | ---: |
| `ApplyCalleeShrinks`, inclusive | 58% |
| `ApplyCalleeStores`, inclusive | 47% |
| `ApplyCalleeStores`, the loop that copies each body event (typecheck_builtins.h:1964) | 11% |
| `FlatMap::Probe` | 12% |
| `ReplaceStoreEventLog` | 7% |

- This is what the 12 November record found after patches 20–29: each call
  replays every store event of its callee. Changing that is a redesign of
  the analysis, not a patch.
- `GOOSE_PGO=1` on build.sh trains the checker on the port and was worth
  1.29× on 12 November.
- Deleting the scoped compiler (step 4) removes about 40% of the program
  the checker has to analyse.

## goose-to-wasm

../goose-to-wasm does not finish its lifetime pass on the port: it stops
after 884 s with its 2 GiB region full
([its notes](https://github.com/mewhhaha/goose-to-wasm/blob/main/CONTINUE.md)).
Until it does, the patched upstream Goose is the only compiler that builds
the port.

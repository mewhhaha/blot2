# Finish the Goose compiler and retire Zig

The owner's direction (15 November 2026):

- "add some more patches to goose to make it faster until goose to wasm is
  ready. And try to finish the goose compiler so we can retire zig."
- Later the same day: "make a path to get goose compiler working and the
  zig one deprecated and we can work on compiler times after that."

So the order is: a working Goose compiler, Zig deprecated, then compile
times.

## Where the port stands (15 November 2026)

compiler-goose/ was the scoped compiler as the Zig source stood at 44ee94f4
(12 November). It matched Zig then on Ink's suite and on Gdev Main's Wasm
([executable](../benchmarks/evidence/qualification/2026-11-12-goose-first-executable.json),
[Ink](../benchmarks/evidence/qualification/2026-11-12-goose-ink-parity.json),
[speed](../benchmarks/evidence/measurements/2026-11-13-goose-compile-speed.json)).
The Zig compiler then replaced the scoped backend with the direct one and
deleted about 170,000 lines.

The port now follows that cut:

- **Deleted:** the 214 Goose modules whose Zig originals are gone (scoped
  backend, evaluator, scoped runtime, retained revisions, the checker's
  cross-revision reuse), 41 Goose-only modules that served them (helpers,
  worker packets, the old driver) and 36 laws that tested them.
- **Builds:** compiler-goose/src is a frontend of 166 modules. Goose
  checks it in 33 s and `build.py` links `blotc-goose` in 49 s. Before
  the cut these took 271 s and about 12 minutes, at 10.4 GiB.
- **Frontend parity** (15 November, against the Zig release compiler):
  - `check-project` gives the same JSON records, every counter included,
    on the 33 programs of compiler/fixtures/direct and on 99 of Ink's 112
    test programs. The other 13 differ only in three counters (see "Known
    differences").
  - Lowering diagnostics agree on the 73 programs of
    compiler-goose/tests/uniqueness and on four programs with stores and
    `values.copy` under the prelude.
  - A debug build (`-O0`) checks an Ink test in 250 to 380 ms where the Zig
    release build takes 40 to 65 ms.
- **Parked** in compiler-goose/pending/ (31 modules and 13 laws): the project server,
  dependency bundles, editor completion and native assets. They are ported
  to the 12 November source and wait for step 3.
- **Backend:** writer and runtime are ported and give the same bytes as
  Zig (`python3 compiler-goose/tools/test_direct.py`).

compiler-goose/source-correspondence.json lists every Zig file with where
its Goose module is.

## Steps

Each step ends with a comparison against the Zig compiler.

1. **Frontend up to today's Zig.** Done for what compiles a program: the
   store `place = value` (parser, checker, Core lowering), the storage
   rule for a generalized `let`, rebinding without generalization,
   associated members imported on first lookup, the uniqueness pass, and
   the project commands `parse-project` and `check-project`.
   Left: the lexer's keyword precheck and ASCII fast path (speed only),
   and the leftovers under "Known differences".
2. **Direct backend.** Port types (584 lines of Zig), emit (674), function
   (3,875), direct (121) and the compile interface. Compare the Wasm for
   compiler/fixtures/direct byte for byte.
3. **Projects.** Bring compiler-goose/pending/ back into src against
   today's Zig: the project pipeline of main.zig, `serve-project` (it now
   builds each revision fresh), dependency bundles, `migrate-stores`,
   native assets. Checking is serial; the worker processes of the old port
   are gone.
4. **Parity.** The guest suite (it takes the compiler as an argument),
   Ink's suite through Pen, and the Gdev frame.
5. **Deprecate Zig.** Point the scripts, CI and docs at `blotc-goose`.

Then compile times, as the owner ordered.

## Known differences from Zig that remain in src

- Core still has the four declaration-dependency tables Zig dropped in
  f429ffd8, and `reuse/declaration_dependencies.goose` still fills them.
  Nothing reads them.
- `numeric_proof_bodies` still has `debits` and `frontier`; nothing fills
  them.
- Modules keep the directory their Zig file had on 12 November
  (`src/eval/type_evidence.goose` is `check/type_evidence.zig` today).
- `check/check_scheme_import.goose` still has the helpers the reuse cache
  used (Zig removed 98 lines); nothing calls them.
- **Hash-map order.** `memberTemplates` walks the contract names in the
  order of a hash map, and Goose's `dictionary` orders them differently
  from Zig's. The same schemes are imported in another order, so
  `type_nodes`, `checker.associated_steps` and `checker.inference_steps`
  differ by a few units in a module that declares a contract beside other
  declarations (std/codec, std/equality, std/text; 13 Ink tests through
  lib/codec). Diagnostics and the set of imported schemes are the same.

## Making Goose faster

The lean program removed the cost that mattered: one build is 49 s.

For the record, where the time went on the whole port (133 stack samples
of the emit, 15 November):

| Where | Share |
| --- | ---: |
| `ApplyCalleeShrinks`, inclusive | 58% |
| `ApplyCalleeStores`, inclusive | 47% |
| `ApplyCalleeStores`, the loop that copies each body event (typecheck_builtins.h:1964) | 11% |
| `FlatMap::Probe` | 12% |
| `ReplaceStoreEventLog` | 7% |

- Each call replays every store event of its callee. Changing that is a
  redesign of the analysis, not a patch.
- `GOOSE_PGO=1` on build.sh trains the checker on the port: 233 s against
  271 s on the whole port, same C once the absolute source path is
  removed. It needs `libclang-rt-18-dev` and takes 13 minutes to build.
- No new patch was added on 15 November.

## goose-to-wasm

../goose-to-wasm did not finish its lifetime pass on the whole port: it
stopped after 884 s with its 2 GiB region full
([its notes](https://github.com/mewhhaha/goose-to-wasm/blob/main/CONTINUE.md)).
It has not been tried on the lean program.

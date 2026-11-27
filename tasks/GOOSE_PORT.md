# The Goose compiler replaced the Zig compiler

The owner's direction (15 November 2026):

- "add some more patches to goose to make it faster until goose to wasm is
  ready. And try to finish the goose compiler so we can retire zig."
- "make a path to get goose compiler working and the zig one deprecated and
  we can work on compiler times after that."
- "Yes make the switch and delete the zig compiler."

All three are done. The compiler is compiler-goose/. The Zig compiler,
compiler/, was removed on 15 November 2026; commit 359b14f6 is the last
with it. Compile times are next.

## The comparison before Zig was removed

compiler-goose/ was the scoped compiler as the Zig source stood at 44ee94f4
(12 November). The Zig compiler then replaced the scoped backend with the
direct one and deleted about 170,000 lines. The port followed that cut and
was then brought up to the Zig source of 15 November.

`compiler-goose/build/squidc-goose` now has every command of `squidc`:
`lex`, `parse`, `check`, `build`, `parse-project`, `check-project`,
`build-project`, `dependencies`, `serve-project` and `migrate-stores`.

Against the Zig release compiler:

| What | Result |
| --- | --- |
| Guest and host suite | 1,054 pass, 0 fail, 101 ignored, as for Zig |
| The 187 fixture programs (now compiler-goose/tests/fixtures) | Wasm and records identical on 183; the other four differ in one counter (see "Known differences") |
| Ink's 112 test programs, `build-project` | Wasm byte-identical |
| Ink's suite through Pen (`pen test-squid`) | Same log line for line, timings aside: 268 passed, 1 failed, 3 did not compile, in 73 modules |
| Gdev Main | Wasm byte-identical through `serve-project` (2,720,970 bytes, sha256 af9f24dd…); its first Pen frame matches the recorded hashes (frame.png c1ff619f… on the software driver, frames.trace 86d50101…) |
| `migrate-stores` on compiler-goose/tests/uniqueness (73 programs, 78 sites) and a dry run on Gdev | Same output and same rewritten files |
| Dependency bundles | Same size as Zig's; only the 63 header bytes that hold the compiler identity differ. Each compiler declines the other's bundle (SchemaMismatch) |

The same holds with four forked checkers (see "Parallel checks"): the
suite, Gdev Main's Wasm and Ink's log through Pen.

compiler-goose/source-correspondence.json lists every Zig file with where
its Goose module is.

## Steps

1. **Frontend up to today's Zig.** Done.
2. **Direct backend.** Done: types, emit, function, direct and the compile
   interface, with Zig's hash-map order reproduced where output depends on
   it.
3. **Projects.** Done: the project pipeline of main.zig, `serve-project`
   (each revision built fresh), dependency bundles, `migrate-stores`,
   native assets, editor completion and parallel module checks.
4. **Parity.** The table above.
5. **Switch and delete Zig.** Done; see the next two sections.

Then compile times, as the owner ordered.

## What the switch changed

- **References.** The Goose compiler's tests compared it with the Zig
  compiler. They now compare it with records of what Zig produced on 15
  November: tests/fixtures/expected.json (187 programs: exit code, Wasm
  hash and size, records), tests/uniqueness/expected.json (lowering
  diagnostics of 73 programs) and tests/direct/NAME.expected (backend
  bytes). `--record` rewrites a record after a deliberate change.
- **Scripts.** `deno task build:compiler` and `build:compiler:dev` build
  the Goose compiler (optimized to build/squidc-goose, debug to
  build/squidc-goose-dev). `deno task test:compiler` is the gate: tooling
  tests, the optimized build, the three references, the package and every
  guest and host test. The tests' default compiler path, `pack_native.ts`,
  editor/helix and the benchmark tools name the Goose compiler.
- **CI** builds the Goose compiler (clang, cmake, ninja; the patched Goose
  is cached) and runs `deno task check`.
- **Siblings.** ../ink and ../gdev run
  ../squid-lang/compiler-goose/build/squidc-goose from their pen.json; Pen's
  tests, example check and CI, and Ink's CI, build and run it too. A
  machine that builds them needs the compiler built first
  (`deno task build:compiler`).
- **Generators.** Two generators read Zig declarations: the dependency
  bundle codecs and the JSON adapters. What they read is now recorded in
  tools/dependency-wire-model.json (the bundle format: 203 types) and
  tools/json-union-model.json (15 unions), and both are edited by hand
  from here on. The codec generator refuses to run when a Goose type on
  the wire gains or loses a field or variant the model does not list.
- **A test fixture.** The fake completion peer of the LSP tests was a Zig
  program built with `zig build-exe`; it is now C, built with `cc`
  (tests/host/fixtures/completion_peer.c). The tests no longer need Zig.
- **A crash found while recording.** A `pack` without a selected dictionary
  failed an assertion in the backend, because only frozen modules had the
  table its child is read from. No test had reached it. The core builder
  now fills the table.

## What went with Zig

- **Zig's native test suite** (`zig build test`): the unit tests of the
  lexer, parser, checker, Core lowering and backend, with their
  allocation-failure sweeps. The Goose compiler has no unit tests of its
  own beyond the two direct-backend laws. What tests it is the guest and
  host suite and the three recorded references.
- **The Zig lint** (`deno task lint:zig`, zig-analyzer) and the scripts
  around the native suite: `check:dev`, `test:native`, the native test
  inventory, shards and costs, and their tooling tests.
- **Benchmark tools for Zig's own build**: compiler_iteration.py,
  development_cycles.py and zig_time_report.ts. The profilers that remain
  in benchmarks/tools name frames by Zig source file and need redoing.
- **The Zig-oracle runner** compiler-goose/tools/qualify_compiler.ts with
  its fixtures, and compiler-goose/pending/: three modules that only Zig's
  tests used and 13 laws written for the 12 November interfaces.
- **The unfinished memory-model phase 2 pass** exists only in Zig, on
  branch `wip/memory-phase2-own` (0afccb55). It has to be ported to Goose
  when that work resumes.
- `compiler-goose/source-correspondence.json` still says which Zig file
  each Goose module came from.

## Parallel checks

`--frontend-workers N` checks ready modules in up to N forked copies of
the compiler process (src/reuse/project_check_workers.goose).

- A copy has the whole compiler state as it stood at the fork. Only its
  answer crosses a pipe: the checked module, in the packet encoding the
  port already had.
- A module with a diagnostic, and one whose copy fails, is checked again
  in the parent. Diagnostics therefore never depend on N.
- Zig uses threads that share the checker's memory. Goose threads cannot:
  each gets its own copy of every global, and the checker's pools are not
  flat values.
- It is correct and slow. On Gdev Main four checkers take 3.8 s and two
  take 4.3 s where one takes 1.9 s: 264 forks, and each checked module is
  encoded, piped and decoded. So the Goose compiler defaults to one
  checker (Zig defaults to four). Pen does not pass the option, and
  scripts/integration/build_gdev.ts passes it only when given, so both
  run one.

## Speed

Release builds of both compilers, 15 November 2026, on the 4-core
development container. Each row is the same work; the Wasm is the same.

| What | Zig | Goose |
| --- | ---: | ---: |
| Gdev Main through `serve-project` (264 modules, 2.5 MB of source) | 0.9 s with 4 checkers, 1.37 s with 1 | 1.9 s with 1 checker, 3.8 s with 4 |
| Ink tests/six-more-physics, `build-project` (best of 7) | 127 ms | 200 ms |
| Ink tests/app-words, `build-project` (best of 7) | 62 ms | 89 ms |
| Ink's suite through Pen | 3.3 s | 4.7 s |
| Guest and host suite | 21 s | 28 s |

The Goose column is with one checker, its default.

A server that builds the same Ink test 30 times stays at 37 MB: the
compiler returns its memory after each build.

## The memory record

The compilation records carry `memory` (live, peak and allocated bytes,
allocations). In Zig these count every allocation of the command. In the
Goose compiler they count its pooled owners: the buffers it takes and
releases by hand, which is where the port keeps what Zig allocated.
An array that belongs to a scope is released with the scope and is not
counted. `memory_scope` in each record says so. `--profile` charges the
same requests to the phase where they happen.

The guest suite asserts `live_bytes == 0` after most builds. That found a
leak the port had from the start: the checker kept the environment rows of
every certified lambda.

## Known differences from the Zig compiler

- Core still has the four declaration-dependency tables Zig dropped in
  f429ffd8, and `reuse/declaration_dependencies.goose` still fills them.
  Nothing reads them.
- `numeric_proof_bodies` still has `debits` and `frontier`; nothing fills
  them.
- Modules keep the directory their Zig file had on 12 November
  (`src/eval/type_evidence.goose` is `check/type_evidence.zig` today).
- `check/check_scheme_import.goose` still has the helpers the reuse cache
  used (Zig removed 98 lines); nothing calls them.
- `reuse/revision_inputs.goose` still has code for retained revisions;
  nothing reaches it.
- native/ still has the request supervisor of the 12 November server
  (request_supervisor.c, request_transport.c, request_cache.c), which
  forked a process for each request. The server no longer uses it: like
  Zig's, it answers every request in the one server process, and an error
  ends that process.
- **Hash-map order** is reproduced where it was found to matter: the
  checker walks its imported names and its globals in the slot order of
  Zig's hash map, and the backend its binding map (support/zigmap.goose
  keeps the same layout).
- **Three counters differ slightly from Zig's.** Diagnostics, the imported
  schemes and the Wasm are the same; the cause was not found before Zig
  was removed. tests/fixtures/expected.json keeps Zig's value beside the
  Goose compiler's for the four fixtures it affects (`type_nodes`, 2 or 3
  more).
  - A module that declares a function with a `where` clause beside
    another declaration ends with one more type node than in Zig (a
    one-element product, appended after every node the two share):
    std/codec, std/equality and std/text have 2 more.
  - Ink's lib/codec takes 6 more `associated_steps` and
    `inference_steps` and has 4 more type nodes; 13 of Ink's 112 tests
    import it.
- The server's request parser checks the whole document's syntax before it
  types any field. Zig's streams, so a request with both a type error and
  a later syntax error is refused as `SyntaxError` here and
  `UnexpectedToken` there. Both end the session.

## Making Goose faster

The lean program removed the cost that mattered: Goose checks the port in
about 55 s, a debug build takes about 85 s and a release build about 7
minutes (Goose's emit 60 s, clang -O2 the rest).

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

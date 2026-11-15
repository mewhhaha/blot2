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
(12 November). The Zig compiler then replaced the scoped backend with the
direct one and deleted about 170,000 lines. The port followed that cut and
was then brought up to today's Zig.

`compiler-goose/build/blotc-goose` now has every command of `blotc`:
`lex`, `parse`, `check`, `build`, `parse-project`, `check-project`,
`build-project`, `dependencies`, `serve-project` and `migrate-stores`.

Against the Zig release compiler:

| What | Result |
| --- | --- |
| Guest and host suite (`deno test -A --parallel tests/guest tests/host -- blotc-goose`) | 1,053 pass, 1 fails, 101 ignored. Zig: 1,054, 0, 101 |
| compiler/fixtures/direct, 33 programs | Wasm and records byte-identical |
| Ink's 112 test programs, `build-project` | Wasm byte-identical |
| Ink's suite through Pen (`pen test-blot`) | Same log line for line, timings aside: 268 passed, 1 failed, 3 did not compile, in 73 modules |
| Gdev Main | Wasm byte-identical through `serve-project` (2,720,970 bytes, sha256 af9f24dd…); its first Pen frame matches the recorded hashes (frame.png c1ff619f… on the software driver, frames.trace 86d50101…) |
| `migrate-stores` on compiler-goose/tests/uniqueness (73 programs, 78 sites) and a dry run on Gdev | Same output and same rewritten files |
| Dependency bundles | Same size as Zig's; only the 63 header bytes that hold the compiler identity differ. Each compiler declines the other's bundle (SchemaMismatch) |

The one failing test is tests/guest/worker_determinism.test.ts. It
requires that `--frontend-workers` checks modules in parallel
(`parallel_jobs >= modules`). The Goose compiler accepts the option and
checks serially. See "What is left".

compiler-goose/source-correspondence.json lists every Zig file with where
its Goose module is.

## Steps

1. **Frontend up to today's Zig.** Done.
2. **Direct backend.** Done: types, emit, function, direct and the compile
   interface, with Zig's hash-map order reproduced where output depends on
   it.
3. **Projects.** Done: the project pipeline of main.zig, `serve-project`
   (each revision built fresh), dependency bundles, `migrate-stores`,
   native assets and editor completion. Checking is serial.
4. **Parity.** The table above.
5. **Deprecate Zig.** Not started. See "What is left".

Then compile times, as the owner ordered.

## What is left before Zig can go

- **Parallel module checks.** Zig checks modules on worker threads when
  `--frontend-workers` is above 1, and one guest test requires it. Goose
  threads cannot share the checker's pools (each thread gets its own copy
  of every global, and a pool is not a flat value), so this needs worker
  processes that exchange packets, as the 12 November port had. The packet
  codecs (src/support/project_packet_codecs.goose) and the native worker
  host (native/platform.c) are still there; the driver for them was
  deleted in the cut. Until then `build_gdev.ts` and Pen run the Goose
  compiler with one checker.
- **Switch the tooling.** scripts/build_compiler.ts, test_compiler.ts and
  pack_native.ts, the default compiler path in the tests, deno.json's
  tasks, CI, editor/helix and the `blotc` path in the sibling pen.json
  files all name the Zig compiler.
- **Zig's own tests.** `zig build test` (the native suite) tests the Zig
  source. The port has laws for the direct backend and the uniqueness pass
  only; compiler-goose/pending/tests holds 13 laws written for the 12
  November interfaces, and they are not run.
- **Speed.** A release build of the Goose compiler is slower than Zig
  (see "Speed" below).

## Speed

Release builds of both compilers, 15 November 2026, on the 4-core
development container. Each row is the same work; the Wasm is the same.

| What | Zig | Goose |
| --- | ---: | ---: |
| Gdev Main through `serve-project` (264 modules, 2.5 MB of source) | 0.9 s with 4 checkers, 1.37 s with 1 | 1.7 s |
| Ink tests/six-more-physics, `build-project` (best of 7) | 127 ms | 200 ms |
| Ink tests/app-words, `build-project` (best of 7) | 62 ms | 89 ms |
| Ink's suite through Pen | 3.3 s | 4.3 s |
| Guest and host suite | 21 s | 26 s |

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
- **Three counters still differ slightly.** Diagnostics, the imported
  schemes and the Wasm are the same; the cause is not found.
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

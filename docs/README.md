# Repository map

Start with [CONTINUE.md](../CONTINUE.md) for the current compiler and
integration frontier, [PLAN.md](../PLAN.md) for active requirements, and
[tasks/STORAGE_REWRITE.md](../tasks/STORAGE_REWRITE.md) for the owned-storage
rewrite scope.

## Code and tests

- [compiler/](../compiler/README.md) is the sole compiler: Zig parses, checks,
  evaluates and emits WebAssembly.
- [host/](../host/README.md) contains Deno clients and tools, including the
  formatter, CLI, package manager, editor integration and guest ABI runtime.
- [tests/guest](../tests/guest) exercises compiled guest behavior;
  [tests/host](../tests/host) covers Deno host APIs;
  [tests/tooling](../tests/tooling) covers build, lint and qualification tools.
- [scripts/integration](../scripts/integration) contains the Gdev and Pen
  integration runners. [generated/parser](../generated/parser) holds generated
  Baba parser assets; the native compiler parses independently.
- [benchmarks/](../benchmarks) contains workloads, Goose comparisons and tools.
  Pinned qualification, measurement and integration records live in
  [benchmarks/evidence](../benchmarks/evidence).

## Documentation

- [Language](language/guide.md): syntax and programming model.
- [Compiler](compiler/ARCHITECTURE.md): architecture, ownership and
  implementation contracts. [Compiler status](compiler/STATUS.md) tracks current
  design state.
- [Deferred work](compiler/DEFERRED_WORK.md): ordinary callbacks after memoized
  demands were removed. [Packed sequences](compiler/PACKED_SEQUENCES.md): the
  immutable List representation pilot, separate from production support.
- [Host](host/packages.md): public Deno APIs, packages, assets and guest ABI.
- [Qualification](qualification/): candidate-specific qualification reports.

The counted-storage and ABI 8 data-stack backends remain live. Task 120 owns the
unfinished retirement; moving files does not change that status.

## Historical evidence

Raw result files, pins, source hashes, rejected experiments and candidate
identities under `benchmarks/evidence/` are preserved as recorded. A result
qualifies only the source and toolchain it names. Historical command transcripts
retain their original paths; use the current entrypoints above for new runs.
Superseded plans and issue diaries remain available at their original pinned
revisions:

- [Original compiler programme](https://github.com/mewhhaha/blot2/blob/541ff890f1df53b5fe8572bd7f2bc41230f2fddb/PLAN.md)
- [Earlier language proposals](https://github.com/mewhhaha/blot2/blob/541ff890f1df53b5fe8572bd7f2bc41230f2fddb/DESIGN.md)
- [Counted-runtime completion plan](https://github.com/mewhhaha/blot2/blob/541ff890f1df53b5fe8572bd7f2bc41230f2fddb/FINISH_PLAN.md)
- [Dated issue triage](https://github.com/mewhhaha/blot2/blob/541ff890f1df53b5fe8572bd7f2bc41230f2fddb/ISSUE_TRIAGE.md)
- [Development timing diary](https://github.com/mewhhaha/blot2/blob/541ff890f1df53b5fe8572bd7f2bc41230f2fddb/DEVELOPMENT_TURNAROUND.md)
- [Earlier archived work logs](https://github.com/mewhhaha/blot2/tree/e2fbe95b4ece3e2d4fd442d95274bb6156815705)

See the [cleanup record](repository-cleanup.md) for the previous cleanup and the
[root README](../README.md) for development commands.

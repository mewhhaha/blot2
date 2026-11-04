# Repository map

[CONTINUE.md](../CONTINUE.md) records the current compiler, measurements and
qualification frontier. [PLAN.md](../PLAN.md) records the active direction;
[tasks 110–121](../tasks/STORAGE_REWRITE.md) retain the unfinished rewrite
requirements.

- [zig-native](../zig-native/README.md): the only compiler, including its
  parser, checker, evaluator, retained project server, Wasm backends and
  regression laws.
- [compiler](../compiler/README.md): Deno client, CLI, package tooling, Wasm
  host, formatter, derive generator and editor integration. These are active
  tools.
- `grammar.baba`, `baba.json` and `generated/wasm`: the formatter/derive parser.
  Zig parses independently. `editor/` contains the highlighting grammar and
  Helix setup.
- `std/`, `examples/` and `benchmarks/`: the language library, executable
  examples and measured workloads. `scripts/` contains build, qualification,
  profiling and integration runners.
- `zig-native/qualification`, `zig-native/measurements`, benchmark results and
  storage-handoff evidence preserve pinned observations. Historical results
  qualify their own candidate, not the current source.

Current contracts are the [language guide](../compiler/guide.md),
[design direction](../DESIGN.md),
[ownership contract](../zig-native/CONTRACT.md),
[scoped storage](../zig-native/SCOPED_STORAGE.md) and
[guest ABI](../compiler/guest-abi.md). The counted and data-stack backends are
both still live;
[task 120](../tasks/120-retire-counted-storage-and-language-tasks.md) owns
semantic retirement.

The [cleanup record](repository-cleanup.md) distinguishes removed leftovers from
live implementation and preserved evidence.

## Historical plans

Superseded cumulative plans and diaries are available at the pinned pre-cleanup
revision:

- [Original compiler programme](https://github.com/mewhhaha/blot2/blob/541ff890f1df53b5fe8572bd7f2bc41230f2fddb/PLAN.md).
- [Earlier language proposals](https://github.com/mewhhaha/blot2/blob/541ff890f1df53b5fe8572bd7f2bc41230f2fddb/DESIGN.md).
- [Counted-runtime completion plan](https://github.com/mewhhaha/blot2/blob/541ff890f1df53b5fe8572bd7f2bc41230f2fddb/FINISH_PLAN.md).
- [Dated issue triage](https://github.com/mewhhaha/blot2/blob/541ff890f1df53b5fe8572bd7f2bc41230f2fddb/ISSUE_TRIAGE.md).
- [Development timing diary](https://github.com/mewhhaha/blot2/blob/541ff890f1df53b5fe8572bd7f2bc41230f2fddb/DEVELOPMENT_TURNAROUND.md).

[Earlier archived work logs](https://github.com/mewhhaha/blot2/tree/e2fbe95b4ece3e2d4fd442d95274bb6156815705)
remain available too. Active task requirements and dedicated qualification
records stay in the working tree. Archiving a plan does not complete its work.

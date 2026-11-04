# Compiler host tools

The compiler is implemented in [zig-native](../zig-native/README.md). This
directory contains its Deno project client, CLI, WebAssembly guest host,
formatter and language documentation. Zig is the only compiler; `createCompiler`
starts the native project server, and CLI checking/builds invoke `blotc`
directly.

Wasm emission still selects between the live counted-storage and ABI 8
data-stack backends.
[Task 120](../tasks/120-retire-counted-storage-and-language-tasks.md) makes
data-stack storage unconditional and retires the counted runtime.

The Baba parser in `syntax.ts` serves the formatter and derive source generator.
Those tools read and rewrite Blot source; they do not perform type/effect
inference, compile-time evaluation or Wasm emission. The native compiler parses
source independently and checks generated source through the same language
pipeline. Editor completion also delegates semantic queries to Zig.

The package root exports `createCompiler({ entry, executable? })`.
`createZigProjectCompiler` exposes the explicit native transport. Both support
retained revisions and unsaved source overrides. See
[the project API](../zig-native/PROJECT_CLIENT.md). The `inferenceBudget`
setting controls ordinary inference and associated work through project checking
and compile-time evaluation; its default is 1,000,000.

The default packaged API and standalone hosts extract
`generated/compiler/blotc.gz`. Use `deno task package:build` to build and pack
the release, or `deno task package:pack` to refresh the payload from an already
built release. Keep it with the matching standard library; pass `executable`
explicitly when testing a development compiler.

For fresh and retained compile costs, profiling commands and the current
performance priorities, see [CONTINUE.md](../CONTINUE.md) and its pinned
measurement reports.

[Typed asset imports](assets.md) register explicit parsers that produce ordinary
typed modules and optional host resource snapshots. JSON data, shader input
types, and asset references share this interface.

## Prelude and operators

The public API and Deno CLI load `std/prelude.blot` by default. Set
`prelude: null` or `--prelude none` to opt out. Operators, collection helpers,
monadic adapters and library functions are ordinary Blot declarations; consult
[the language guide](guide.md) and [standard library](../std/README.md).

## Evaluation and Wasm representation

Compile-time evaluation uses the native operation, nesting and allocation
limits. It does not reproduce retired Bend step counts. Runtime values use the
[guest ABI](guest-abi.md); hosts pass explicit callable capabilities into entry
functions. Lists and arrays have distinct types and representations.

Language tasks are retired in the owned-storage model. ABI 8 rejects task
metadata and imports; ordinary task programs can still reach the counted backend
until task 120 completes. Isolated host workers and data queues exchange copied
numeric packets. Ordinary Foreign suspension remains supported. See
[host workers](guide.md#host-workers) and the [current guest ABI](guest-abi.md).

The repository [development instructions](../README.md#development) build the
compiler used by these host tools.

Run `deno task test:compiler` from the repository root. Tests cover compiler
ownership, language behavior, generated Wasm, host lifetimes, retained builds,
failed-edit recovery, packaging, and command-line compilation.

The native project client accepts `frontendWorkers: 1..16` (default four) for
independent fresh module checks. Retained edit checking retains its existing
cutoff behavior. This option is separate from evaluator `semanticWorkers` and
optimizer `codegenWorkers`; see
[the project API](../zig-native/PROJECT_CLIENT.md). Public idiomatic Blot/Rust
sources and compile/runtime methodology are in
[benchmarks/idiomatic](../benchmarks/idiomatic/README.md), with measured tables
in the
[root README](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/README.md#idiomatic-blot-and-rust-benchmarks).

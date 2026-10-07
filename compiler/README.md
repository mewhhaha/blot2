# Compiler host tools

The compiler is implemented in [zig-native](../zig-native/README.md). This
directory contains its Deno project client, CLI, WebAssembly guest host,
formatter and language documentation. No second compiler backend is selected at
runtime.

The package root exports `createCompiler({ entry, executable? })`.
`createZigProjectCompiler` exposes the explicit native transport. Both support
retained revisions and unsaved source overrides. See
[the project API](../zig-native/PROJECT_CLIENT.md).

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

Run `deno task test:compiler` from the repository root. Tests cover compiler
ownership, language behavior, generated Wasm, host lifetimes, retained builds,
failed-edit recovery, packaging, and command-line compilation.

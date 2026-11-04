# Deno host

This directory contains the Deno client and host tools for the Zig compiler:
CLI, package manager, formatter and derive generator, editor integration,
project client, diagnostics, and WebAssembly guest and ABI runtime. It does not
parse and compile programs independently; semantic queries and emission are
handled by [the Zig compiler](../compiler/README.md).

The Baba grammar and parser inputs are in `host/parser/`; generated parser
outputs are in [generated/parser](../generated/parser). The compiler parses
source independently.

## Interfaces and tests

- The package exports the public API from [mod.ts](../mod.ts). The project
  client and protocol are described in
  [PROJECT_CLIENT](../docs/compiler/PROJECT_CLIENT.md) and
  [PROJECT_PROTOCOL](../docs/compiler/PROJECT_PROTOCOL.md).
- The guest runtime follows the [guest ABI](../docs/host/guest-abi.md). Host
  tests are in [tests/host](../tests/host); guest behavior tests are in
  [tests/guest](../tests/guest); tool tests are in
  [tests/tooling](../tests/tooling).
- Host documentation: [packages](../docs/host/packages.md),
  [assets](../docs/host/assets.md), [derive](../docs/host/derive.md), and the
  [language guide](../docs/language/guide.md).

Use `deno task test:compiler` for the full compiler test gate. It does not
replace the separate application qualification described in
[CONTINUE.md](../CONTINUE.md). The counted backend is still reachable for some
programs; task 120 owns its unfinished retirement.

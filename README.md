# Blot 2

Deno-hosted tooling with a native compiler written in Bend 2. The first
executable `.blot` slice uses Baba for lexing/parsing, then Bend for source
lowering, type/effect checking, const evaluation, and Wasm emission. Baba is
pinned to 9.0.1 through its JSR npm mirror. The executable core includes a
generic source prelude, closures, algebraic data, matching, and source-defined
operators. It does not yet implement the entire target language.

The [design baseline](DESIGN.md) records the agreed direction for Blot 2,
including immutable rebinding with `self`, `data` declarations and `type`
aliases, pure `let`, effect-permitting `use`, resolver-valued `do` blocks,
source-defined operators, demand-driven parameters, const-time type programming,
declaration tags, and explicit imports and exports. It also lists open decisions
and current implementation status.

Read [the syntax showcase](examples/syntax.blot) to judge the proposed language
in one file. Unsettled forms are marked `PROPOSAL`; this is a design example,
not an executable parser fixture. The [ECS specimen](examples/ecs.blot) adds
component/resource tags, inferred system requirements, explicit world/entity
provider boundaries, const world construction, and proposed SIMD APIs.

## Native Bend compiler

Requires Deno 2, **Bend 2.0.5**, Bun (used by the Bend launcher), and clang 14+
for native CPU builds. The native transport supports POSIX stdin/stdout.

```sh
just demo       # emit build/example.wasm, execute answer(0) = 42, print ECS plan
just build      # build generated/compiler/blotc, a native executable
just compile    # reuse native compiler; compile prelude example to Wasm
just check      # format/types, Bend proofs, compiler and editor-config tests
just bench      # JavaScript reference compiler timings
just ecs        # compile and execute the gdev-style scalar ECS example
just bench-ecs  # JavaScript reference ECS timings
just bench-native # native vs JS, including pipe transport; native 1/2/4/8 threads
just bench-incremental # edits, 1/2/4/8 lanes, and state-preserving ECS reload
just profile-ecs # save a CPU profile of full 64-system compiles
deno task blot check examples/prelude.blot
deno task blot build examples/prelude.blot build/prelude.wasm
```

Without `just`, use `deno task demo` and `deno task check`. `just build` only
builds the native compiler. The CLI, demo, and ECS demo launch it as a
persistent subprocess: Deno handles Baba parsing; native Bend handles lowering,
inference, const evaluation, and Wasm generation. The versioned binary pipe
protocol keeps diagnostics separate from process stderr. There is no silent JS
fallback. Build tasks enforce the Bend version and disable the launcher's
automatic updates/telemetry for those invocations. The native build applies a
guarded, build-local fix for a reproduced Bend 2.0.5 constructor ownership bug;
it does not modify your Bend installation. See the
[build details](compiler/README.md#run-it). `just compile` and `deno task blot`
reuse the existing binary, so source-only iterations do not rebuild Bend. Run
`just build` after editing the compiler.

[compiler/main.bend](compiler/main.bend) owns analysis and compilation. Bend
implements rank-1 polymorphic inference, transitive first-order ECS effects,
bounded pure const evaluation, closure conversion, and Wasm emission. The Deno
host handles layout, bridges Baba's field-labelled CST, and runs/tests the
output. `LAWS.bend` holds the important rules; `PROOF.bend` proves them, and
every compiler build runs `bend PROOF.bend`.

See [compiler/README.md](compiler/README.md) for the supported core, bootstrap
ABI, tests, and deliberate limits. Start with
[examples/prelude.blot](examples/prelude.blot), which really compiles using
[std/prelude.blot](std/prelude.blot). Generic functions, Maybe/Result,
constructors, captured closures, exhaustive matches, `if let`, guarded `let`,
and symbolic or backtick operators work in const evaluation and Wasm. Host
exports are scalar; closures and algebraic values stay private to each call. The
[executable ECS port](examples/ecs_runtime.blot) adapts the inferred-query
pattern from `../gdev`: component/resource access composes through helper calls,
and the compiler emits real Wasm systems with an explicit host-storage ABI. Its
[provider](compiler/ecs_runtime.ts) uses private typed-array columns and
copy-on-write snapshots. `just ecs` verifies an update and writes
`build/ecs.wasm` plus its inferred `build/ecs.plan.json` for inspection. This is
a U32-only port, not the full reflective `gdev` library or a complete engine.

The separate JavaScript-backed [incremental compiler](compiler/incremental.ts)
keeps declaration, inference, const-evaluation, and relocatable-code caches in a
persistent session. Its caches/job API have not yet moved into the native
process; native requests currently perform full compilation. Independent JS jobs
can use a persistent Deno worker pool. The ECS provider can reload a compatible
artifact while preserving immutable world snapshots; incompatible storage
changes require an explicit migration rather than resetting state. See
[incremental compilation](compiler/README.md#incremental-compilation-and-reload)
for the API, measurements, and current boundaries.

Imports, demand parameters, higher-order effects, type-valued consts, and
source-language arrays/SIMD are not implemented yet. Ordinary compilation still
rejects unhandled ECS effects; the explicit `compileEcs` entry point links them
to the provider. `let` rejects effectful RHSs after inference; `use … <- …`
preserves effects and also compiles for pure scalar computations.
`use expression` compiles identically to `use _ <- expression`. Resolver headers
(`do try:`) and forwarding returns (`return $`) are recognized, but custom
resolver execution remains unsupported and receives explicit lowering
diagnostics. The executable prelude example does not imply the full syntax
showcase or ECS specimen compiles.

## Baba generation

Generation only requires Deno 2. Dependencies are fetched automatically and
pinned in `deno.lock`.

```sh
deno task generate
```

Generation writes the Wasm lexer, parser plan, TypeScript bindings, and editor
query fragments and compact-CST schema to `generated/`. Regenerate these
artifacts after changing the grammar, metadata, or Baba version.

Blot uses Baba's version-3 general frontend profile. Use the generated
`createParser({ bytes, plan }).lex(source)` for lexing and Baba's `CpuFrontend`
from `@mewhhaha/baba/runtime/webgpu` for parsing the plan. The generated Wasm
parser's `parse()` supports only Baba's strict profile, so it cannot parse this
grammar. The CPU frontend does not require WebGPU.

The parser expects layout markers (`U+E000` newline, `U+E001` indent, `U+E002`
dedent). [compiler/syntax.ts](compiler/syntax.ts) inserts these markers,
preserves source positions, and materializes Baba's CST.
[compiler/lower.bend](compiler/lower.bend) resolves source names and lowers to
core. The host does not duplicate the parser or implement Blot's typing rules.

## Helix highlighting

From this checkout:

```sh
just install
hx examples/syntax.blot
```

Without `just`, run `deno task helix:install` directly.

Requires the Tree-sitter CLI 0.26.3 (with its native JavaScript runtime) and a C
compiler, plus Helix for the installation health check. The installer builds and
checks the editor grammar, then overrides the global `blot` language
registration and runtime under `$XDG_CONFIG_HOME/helix`, or `~/.config/helix`
when `XDG_CONFIG_HOME` is unset. It uses the
[language definition](editor/helix/languages.toml), disables the legacy Blot LSP
and auto-formatting, and leaves unrelated languages and workspace-trust settings
unchanged.

Re-running updates the same managed Blot block without duplicating it. Replaced
files and incompatible old queries are backed up under `helix/blot-backup-*`;
unchanged installs do not create another backup. The separate `blot2` runtime
from the initial setup is retired. Restart Helix after installing; `.blot` files
now use `blot` everywhere, without project-local configuration or a trust grant.

The installer verifies `hx --health blot` outside this checkout so a missing
global registration cannot be hidden by a project-local override.

The [editor grammar](editor/tree-sitter-blot2/grammar.js) is a permissive
highlighting grammar for the showcase, including its `PROPOSAL` forms. It
recognizes named and associated functions, backtick infix calls, `data`/`type`
declarations, `#[declaration_tags]`, operator headers, `@` intrinsics,
demand-driven parameters, `use` bindings, resolver headers, `return $`,
`if let`/`let … else:` patterns, unions, arrays, `self`, and nested text
interpolation. It does not validate indentation, expressions, or the language's
semantics, and it is not generated from the narrower executable Baba grammar.

```sh
deno task check:editor
```

This checks highlight captures and parses both specimens for editor-grammar
errors. The normal `deno task check` does not require Tree-sitter. Conversely,
`just install` does not require Bend or run compiler tests.

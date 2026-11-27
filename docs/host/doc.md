# Documentation Generator (`squid doc`)

`squid doc` extracts compiler-checked public APIs directly from `squidc doc-project`, merges Markdown doc comments, resolves cross-module symbol links, runs doctests, and exports either static Markdown or a self-contained static HTML documentation site with live browser-runnable WebAssembly examples.

## Quick start

```bash
# Compact API summary or single-module Markdown
squid doc std
squid doc std/vector
squid doc ../ink
squid doc ink/codec

# Search symbols, signatures, and doc comments
squid doc std --search Vec2.dot

# Verify all intra-doc links and execute runnable code examples
squid doc std --check-links --test

# Export static Markdown (INDEX.md, API.md, modules/*.md)
squid doc std --out docs-md

# Export static HTML site with search + precompiled runnable Wasm examples
squid doc std --html --out docs-site

# Machine-readable JSON (schemaVersion: 1)
squid doc std/codec --json
```

## Target discovery

`squid doc [TARGET]` resolves targets in this order:

1. **`std` / `std/<module>`** — documents the bundled or `--std-root` standard library.
2. **Project aliases (`squid.json` or `pen.json`)** — resolves `<alias>` or `<alias>/<module>` from `squid.json` dependencies or `pen.json` `compiler.settings.imports` (for example `squid doc ink` or `squid doc ink/codec`).
3. **File or directory path** — documents a single `.sq` file or recursively discovers library `.sq` files in a directory (recognizing `pen.json` library roots automatically).

## Writing doc comments

No special syntax is required — existing `//` comments work immediately:

- **Module header comments:** use leading `//!` lines at the top of a file, or a leading `//` comment block separated by a blank line (or preceding `import`).
- **Declaration, constructor, and field comments:** place contiguous `//` or `///` lines directly above the declaration (attributes like `@[inline]` may sit between the comment and declaration).
- **Visibility:** `private` declarations and the internal representation of `is opaque` types are omitted unless `--include-private` is passed.
- **Exact compiler types:** inferred return types, `own` parameter modes, effect rows (`! { ... }`), `where { ... }` constraints, and trait implementations are filled in directly from the type checker.

## Markdown & intra-doc symbol links

Doc comments support full Markdown (headings, lists, GFM tables, blockquotes, GitHub callouts `[!NOTE]`/`[!TIP]`/`[!WARNING]`, inline code, and external links) plus Rustdoc-style intra-doc links:

- `` [`Vec2`] `` — links to a symbol in the current module (or unique package-wide symbol).
- `` [`std/vector/Vec2.dot`] `` or `` [`geom/Point`] `` — qualified cross-module link.
- `` [dot product](`Vec2.dot`) `` or `[dot product](squid:Vec2.dot)` — custom link label.

Pass `--check-links` in CI to fail on any unresolved symbol link.

## Runnable code blocks & online Wasm examples

Fenced ```` ```squid ```` blocks inside doc comments are checked and executed by `squid doc --test` and precompiled into self-contained ABI 8 `.wasm` bundles by `squid doc --html --out <dir>`:

- **```` ```squid ````** (or ```` ```squid run ````) — compiles to ABI 8 Wasm and runs. Bare expressions/statements automatically import referenced public items from the documented module and wrap into `io`.
  - Add a trailing `// => <expected>` comment on the final expression to assert its output (supports `U32`, `F32`, `Bool`, `Unit`, `Text`, `#[U32]`, and `#[F32]`).
  - First-class `test "..."` and `test expect_trap "..."` blocks compile with `--test` and run every test.
- **```` ```squid check ````** / **```` ```squid no_run ````** — type-checked without requiring an ABI 8 `io` return type or executing at runtime.
- **```` ```squid ignore ````** — displayed in docs without compiling.

The generated HTML site embeds compiled examples in `examples.js` alongside a zero-dependency pure-JS ABI 8 + `squid:traps` v1 + BTST v1 runner (`runner.js`). Clicking **▶ Run** executes the WebAssembly module directly in the browser with no backend server (compatible with GitHub Pages, static CDNs, and local `file://` previews).

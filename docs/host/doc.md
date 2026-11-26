# Documentation Generator (`blot doc`)

`blot doc` extracts compiler-checked public APIs directly from `blotc doc-project`, merges Markdown doc comments, resolves cross-module symbol links, runs doctests, and exports either static Markdown or a self-contained static HTML documentation site with live browser-runnable WebAssembly examples.

## Quick start

```bash
# Compact API summary or single-module Markdown
blot doc std
blot doc std/vector
blot doc ../ink
blot doc ink/codec

# Search symbols, signatures, and doc comments
blot doc std --search Vec2.dot

# Verify all intra-doc links and execute runnable code examples
blot doc std --check-links --test

# Export static Markdown (INDEX.md, API.md, modules/*.md)
blot doc std --out docs-md

# Export static HTML site with search + precompiled runnable Wasm examples
blot doc std --html --out docs-site

# Machine-readable JSON (schemaVersion: 1)
blot doc std/codec --json
```

## Target discovery

`blot doc [TARGET]` resolves targets in this order:

1. **`std` / `std/<module>`** — documents the bundled or `--std-root` standard library.
2. **Project aliases (`blot.json` or `pen.json`)** — resolves `<alias>` or `<alias>/<module>` from `blot.json` dependencies or `pen.json` `compiler.settings.imports` (for example `blot doc ink` or `blot doc ink/codec`).
3. **File or directory path** — documents a single `.blot` file or recursively discovers library `.blot` files in a directory (recognizing `pen.json` library roots automatically).

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
- `` [dot product](`Vec2.dot`) `` or `[dot product](blot:Vec2.dot)` — custom link label.

Pass `--check-links` in CI to fail on any unresolved symbol link.

## Runnable code blocks & online Wasm examples

Fenced ```` ```blot ```` blocks inside doc comments are checked and executed by `blot doc --test` and precompiled into self-contained ABI 8 `.wasm` bundles by `blot doc --html --out <dir>`:

- **```` ```blot ````** (or ```` ```blot run ````) — compiles to ABI 8 Wasm and runs. Bare expressions/statements automatically import referenced public items from the documented module and wrap into `#entry`.
  - Add a trailing `// => <expected>` comment on the final expression to assert its output (supports `U32`, `F32`, `Bool`, `Unit`, `Text`, `#[U32]`, and `#[F32]`).
  - First-class `test "..."` and `test expect_trap "..."` blocks compile with `--test` and run every test.
- **```` ```blot check ````** / **```` ```blot no_run ````** — type-checked without requiring an ABI 8 `#entry` return type or executing at runtime.
- **```` ```blot ignore ````** — displayed in docs without compiling.

The generated HTML site embeds compiled examples in `examples.js` alongside a zero-dependency pure-JS ABI 8 + `blot:traps` v1 + BTST v1 runner (`runner.js`). Clicking **▶ Run** executes the WebAssembly module directly in the browser with no backend server (compatible with GitHub Pages, static CDNs, and local `file://` previews).

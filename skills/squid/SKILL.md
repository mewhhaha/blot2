---
name: squid
description: Write, check, optimize, and debug Squid vNext code cleanly on the first try using current syntax, ownership rules, algebraic effects, and CLI tooling.
---

# Writing Squid vNext Code

Read [CHEATSHEET.md](../../CHEATSHEET.md) for the condensed one-page syntax table, [skills/squid-diagnostics/SKILL.md](../squid-diagnostics/SKILL.md) whenever `squid check` or `squid build` reports a diagnostic `[CODE]`, and [skills/agent-loops/SKILL.md](../agent-loops/SKILL.md) for the structured `--json` / quick-fix / trap / Stage-0 agent verification workflow.

## Core Mental Model

1. **Pure-by-default functional language with zero-GC in-place ownership.**
   - There is no garbage collector and no Rust `'a` lifetime syntax.
   - Mutable arrays (`#[T]` / `Array T`) update in place via `:=` (`xs[i] := ...`, `xs := self.push v` / `xs := @storage.push self v`) whenever the compiler statically proves unique ownership.
2. **Indentation-sensitive grammar (no `{ ... }` statement blocks).**
   - Functions use `func name (a: T) -> (b: U): R =>` followed by either a single expression (implicit return) or an indented suite with explicit `return`.
   - `->` separates curried parameters; `:` before `=>` introduces the return type.
   - Algebraic data types always use `type Name is data = $Ctor1 T | $Ctor2`, and every constructor reference/pattern starts with `$`.
3. **Strict explicitness.**
   - Array literals use `#[1, 2, 3]` (never bare `[1, 2, 3]`).
   - Boolean operators are `and`, `or`, `not` (`true` / `false`).
   - No implicit `U32` / `F32` numeric conversions (`@u32.to_f32`, `@f32.to_u32`).
   - Array length is `.length` (not `.len`).

## Ownership Recipe

- **Read-only parameter (default):** `func sum (xs: #[U32]): U32 => ...` — borrows `xs` with zero copies; caller keeps ownership.
- **Mutate-and-return parameter:** `func push_one (xs: own #[U32]) -> (v: U32): #[U32] =>` — caller moves `xs` in, callee mutates in place with `xs := self.push v` (or `return @storage.push xs v` / `xs[i] := ...`), and returns `xs` zero-copy.
- **Need to keep the old value after moving or before mutating an alias:** call `.copy` explicitly (`let snap = xs.copy` or `consume xs.copy`).
- **Share read-only in O(1):** `let shared: *#[U32] = freeze xs`.

## Effects Recipe

- Declare with `type Eff is effect = { op: In -> Out }`.
- Invoke with `use res <- Eff.op arg` (never `let res = Eff.op arg`).
- Handle locally with `handler h: Eff => op arg => ...` and `eff.handle h .run value` (or `@handle h thunk` / `layer h1 h2`) before returning from any `io`, `#kernel`, or `spark` comprehension.

## Fast Verification Loop

```sh
deno task squid check path/to/file.sq
deno task squid build path/to/file.sq build/out.wasm
deno task squid explain <CODE>
```

For machine-readable JSON diagnostics (editor/tooling integration), append `--json`.

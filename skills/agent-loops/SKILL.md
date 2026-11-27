---
name: agent-loops
description: Run tight, structured Squid coding-agent verification loops using v1 JSON diagnostics, safe quick-fix replay, runtime trap triage, and Stage-0 generator provenance.
---

# Squid Coding-Agent Verification Loops

Use this operating loop whenever writing, refactoring, or debugging Squid code. Prefer machine-readable JSON outputs and built-in `explain` lookups over guessing.

## 1. Fast Verification Loop

```sh
# 1. Type-check & ownership-check (works on libraries without io entries, including generator projects)
deno task squid check path/to/module.sq --json

# 2. Run Squid unit & trap tests with structured output
deno task squid test path/to/tests --json

# 3. Look up exact guidance for any canonical or raw diagnostic code
deno task squid explain <CODE>

# 4. Format before finishing
deno task squid fmt path/to/module.sq
```

For Wasm compilation of an `io` / `#kernel` / `#process` root:

```sh
deno task squid build path/to/entry.sq build/out.wasm --json
```

## 2. Reading v1 Enriched Diagnostic JSON

Both `squid check --json` and `squid build --json` emit newline-delimited JSON. Every `"kind": "diagnostic"` record follows schema version `1` while retaining all raw compiler fields:

```json
{
  "kind": "diagnostic",
  "schemaVersion": 1,
  "severity": "error",
  "canonicalCode": "SPENT_VALUE",
  "rawCode": "spent_value",
  "headline": "`row.xs` was already moved at line 5 and can no longer be used here.",
  "scope": "io main",
  "primarySpan": {
    "filename": "/abs/path/app.sq",
    "startByte": 177,
    "endByte": 190,
    "line": 6,
    "col": 14,
    "endLine": 6,
    "endCol": 27,
    "label": "`row.xs` used after move"
  },
  "related": [
    {
      "filename": "/abs/path/app.sq",
      "startByte": 157,
      "endByte": 163,
      "line": 5,
      "col": 16,
      "endLine": 5,
      "endCol": 22,
      "label": "`row.xs` moved here"
    }
  ],
  "fix": "Pass `(row.xs.copy)` at line 5 to keep `row.xs` live, or use the owned value returned by that call.",
  "quickFixes": [
    {
      "title": "Pass `(row.xs.copy)` at move site",
      "startByte": 157,
      "endByte": 163,
      "newText": "(row.xs.copy)",
      "complete": true
    }
  ],
  "docRef": "squid explain SPENT_VALUE (skills/squid-diagnostics/SKILL.md#SPENT_VALUE)"
}
```

Key fields to inspect first:
- **`canonicalCode`** + **`headline`**: exact error class and human/agent summary.
- **`primarySpan`** & **`related`**: 1-based `line`/`col` plus exact UTF-8 byte offsets (`startByte`..`endByte`), including secondary move/borrow/parameter blame sites and multi-file related locations.
- **`fix`** & **`quickFixes`**: concrete remediation and machine-applicable UTF-8 byte edits.
- **`provenance`** (when present): Stage-0 generator metadata (`stage`, `phase`, `module`, `input`, `generator`).
- **`docRef`**: exact `squid explain <CODE>` command and handbook anchor in [skills/squid-diagnostics/SKILL.md](../squid-diagnostics/SKILL.md).

## 3. Applying `quickFixes` Safely and Re-Checking

1. Only auto-apply a quick-fix when `quickFix.complete !== false` and offsets are applied against the exact UTF-8 bytes of the file that produced the diagnostic.
2. Slice the source as UTF-8 bytes (`bytes.subarray(0, startByte) + encode(newText) + bytes.subarray(endByte)`), never JS UTF-16 code units, so non-ASCII comments/strings stay aligned.
3. If applying multiple quick-fixes to the same file, verify their `[startByte, endByte]` ranges do not overlap and apply in descending `startByte` order; otherwise apply `quickFixes[0]` and immediately re-run `squid check --json`.
4. When `quickFixes` is empty (e.g. a Rust-style `fn` signature needing full structural rewrite), follow `fix` and `squid explain <canonicalCode>` instead of forcing partial edits.

## 4. Debugging Runtime Traps (`squid:traps`)

Squid compiles explicit `@panic` messages and bounds-check trap sites into the Wasm `squid:traps` custom section so host runners decode exact failure reasons and source locations:

- In **`squid test`** (`deno task squid test --json`), unexpected traps report the decoded trap kind/message (such as `@panic` payload text or array out-of-bounds index/length) and source file/line alongside the failing test case.
- In **`pen test-squid`**, host integration runs surface the same `squid:traps` payload and location when a guest frame or kernel traps.
- For intentional trap tests (`test expect_trap "..."`), verify the test actually triggers the intended trap rather than failing earlier during setup; for unexpected traps, inspect the reported source line and array indices/bounds first.

## 5. Debugging Stage-0 Generator Pipelines

When a project uses `squid.json` `"generators"`, diagnostics carry a `provenance` object and render `from <input> via <generator> (stage0 <phase>)`. Triage by `provenance.phase`:

| `provenance.phase` | Where the bug lives | Fastest next action |
|---|---|---|
| `compile` | The `.sq` Stage-0 generator itself failed to compile or has an unsupported signature. | Run `squid check <provenance.generator> --json` and fix the generator's syntax/types/signature (`#[U32]` or `{ path, bytes/text }` → `#[U32]` or `Result`). |
| `execute` | The compiled generator trapped at runtime while processing `provenance.input`. | Inspect the decoded trap/panic message and test the generator on `provenance.input` (check bounds, empty input, or malformed token handling). |
| `result` | The generator intentionally returned `$Err message` rejecting `provenance.input`. | Fix the invalid input asset at `provenance.input` according to the generator's error message. |
| `generated_source` | The generator produced Squid source for virtual module `provenance.module` that failed parsing/type-checking/lowering. | Inspect the diagnostic's excerpt (populated automatically from `virtual_source`) and fix the codegen template inside `provenance.generator`. |

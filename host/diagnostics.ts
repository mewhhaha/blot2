import { basename } from "node:path";

export interface RawSpan {
  start: number;
  end: number;
}

export interface RawDispatchCandidate {
  side?: string;
  operand?: string;
  outcome?: string;
  method?: string;
}

export interface RawDispatchExplanation {
  operation?: string | null;
  member?: string | null;
  candidates?: RawDispatchCandidate[];
  truncated?: boolean;
}

export interface RawDiagnosticContext {
  kind?: string;
  message?: string;
  span?: RawSpan | null;
}

export interface RawDiagnosticDetailItem {
  code?: string;
  start?: number;
  end?: number;
  declaration_origin?: RawSpan | null;
  detail_span?: RawSpan | null;
  actual_token?: string | null;
  expected_token?: string | null;
}

export interface RawDiagnosticDetailsObject {
  explanation?: RawDispatchExplanation | null;
  contexts?: RawDiagnosticContext[];
  hole?: Record<string, unknown> | null;
}

export interface RawDiagnosticRecord {
  kind?: string;
  filename?: string;
  stage?: string;
  code: string;
  start: number;
  end: number;
  message: string;
  offset_encoding?: string;
  cause?: string;
  expected_token?: string | null;
  actual_token?: string | null;
  details?: RawDiagnosticDetailItem[] | RawDiagnosticDetailsObject | null;
  origin_kind?: string;
  origin_start?: number;
  origin_end?: number;
  subject_start?: number;
  subject_end?: number;
  holder_start?: number;
  holder_end?: number;
}

export interface DiagnosticExplanationEntry {
  code: string;
  rawCodes: string[];
  title: string;
  summary: string;
  why: string;
  before: string;
  after: string;
  checklist: string[];
}

export interface FormatDiagnosticOptions {
  source?: string;
  displayFilename?: string;
}

interface LineIndex {
  bytes: Uint8Array;
  lineStarts: number[]; // UTF-8 byte offset of each line start
  lines: string[];
}

interface LineCol {
  line: number; // 1-based
  col: number; // 1-based Unicode code-point column
}

interface AnnotatedSpan {
  startByte: number;
  endByte: number;
  marker: "^" | "-";
  label: string;
}

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

const CANONICAL_CODE_MAP: Record<string, string> = {
  GPU_FRONTEND_SYNTAX_ERROR: "SYNTAX_ERROR",
  GPU_FRONTEND_MALFORMED_DELIMITER: "UNMATCHED_DELIMITER",
  GPU_FRONTEND_LEXICAL_ERROR: "LEXICAL_ERROR",
  GPU_FRONTEND_UNTERMINATED_STRING: "UNTERMINATED_STRING",
  GPU_FRONTEND_UNTERMINATED_COMMENT: "UNTERMINATED_COMMENT",
  unknown_name: "UNKNOWN_VALUE",
  unknown_value: "UNKNOWN_VALUE",
};

export function canonicalDiagnosticCode(rawCode: string): string {
  const mapped = CANONICAL_CODE_MAP[rawCode];
  if (mapped) return mapped;
  return rawCode
    .replace(/^GPU_FRONTEND_/, "")
    .replace(/[^A-Za-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .toUpperCase();
}

export const DIAGNOSTIC_CATALOG: Record<string, DiagnosticExplanationEntry> = {
  SYNTAX_ERROR: {
    code: "SYNTAX_ERROR",
    rawCodes: ["GPU_FRONTEND_SYNTAX_ERROR", "syntax"],
    title: "Source declaration or expression does not match Blot syntax",
    summary:
      "The parser encountered a token that cannot appear in this position under Blot's indentation-sensitive grammar.",
    why:
      "Blot differs from Rust/TS/Python in a few specific forms: functions use `func`, curried params use `->`, return types follow `:` before `=>`, indented suites follow `:` or `=>` (no `{ ... }` blocks), and sum types require `type Name is data = $Variant ...`.",
    before: `fn add (a: U32, b: U32) -> U32 {
  return a + b
}`,
    after: `func add (a: U32) -> (b: U32): U32 =>
  return a + b`,
    checklist: [
      "Use `func` (not `fn`/`def`/`function`) and `=>` before the body.",
      "Separate curried parameters with `->` and put the return type after `:` before `=>`.",
      "Use indented suites after `=>`, `if ...:`, `for ...:`, `do:`, `case ... of` — never `{ ... }` braces.",
      "Declare algebraic data types with `type Opt is data = $Some U32 | $Nothing`.",
      "Use `and`, `or`, `not` (not `&&`, `||`, `!`) and `true`/`false`.",
    ],
  },
  UNMATCHED_DELIMITER: {
    code: "UNMATCHED_DELIMITER",
    rawCodes: ["GPU_FRONTEND_MALFORMED_DELIMITER"],
    title: "Unclosed or mismatched delimiter",
    summary:
      "An opening `(`, `[`, `#[`, or `{` does not have a matching closing delimiter at the expected nesting level.",
    why:
      "Nested expressions, array literals `#[...]`, record literals `{ x: 1 }`, and parenthesized negative numbers `(-1.0)` require balanced delimiters on matching indentation.",
    before: `let values = #[1, 2, 3`,
    after: `let values = #[1, 2, 3]`,
    checklist: [
      "Check that every `#[` closes with `]`, every `(` closes with `)`, and every record `{` closes with `}`.",
      "Parenthesize negative arguments to calls: `F32.abs (-2.0)`.",
    ],
  },
  UNSUPPORTED_EXPRESSION: {
    code: "UNSUPPORTED_EXPRESSION",
    rawCodes: ["unsupported_expression"],
    title: "Unsupported expression syntax (commonly bare `[...]` list literal)",
    summary: "This expression form is not supported in executable Blot code.",
    why:
      "Bare `[1, 2, 3]` list literals are retired. Blot has one unified owned array type `#[T]` constructed with `#[1, 2, 3]`.",
    before: `entry func main (): #[U32] => return [1, 2, 3]`,
    after: `entry func main (): #[U32] => return #[1, 2, 3]`,
    checklist: [
      "Prefix array literals with `#`: `#[1, 2, 3]` and empty typed arrays `let xs: #[U32] = #[]`.",
      "Prefix array types with `#`: `#[U32]` or `Array U32`.",
    ],
  },
  UNKNOWN_VALUE: {
    code: "UNKNOWN_VALUE",
    rawCodes: ["unknown_value", "unknown_name"],
    title: "Identifier is not bound in scope",
    summary:
      "The referenced value, function, or constructor does not exist in the current lexical or imported scope.",
    why:
      "Most commonly caused by omitting `$` on a sum-type constructor (`Some 1` instead of `$Some 1`), using `None` instead of `$Nothing`, a typo in a local/global name, or forgetting an `import`.",
    before: `type Opt is data = $Some U32 | $Nothing
entry func main (): Opt => return Some 1`,
    after: `type Opt is data = $Some U32 | $Nothing
entry func main (): Opt => return $Some 1`,
    checklist: [
      "Prefix every data constructor with `$` in expressions and patterns (`$Some x`, `$Nothing`, `$Vec2 { x: 1.0, y: 2.0 }`).",
      "Check for typos against declared `func` / `const` / `let` names.",
      "Verify required modules are imported with `import path` or `import alias`.",
    ],
  },
  MISSING_MEMBER: {
    code: "MISSING_MEMBER",
    rawCodes: ["missing_member", "unknown_field", "unknown_record_field"],
    title: "Receiver type has no field or associated member with this name",
    summary:
      "The `.member` projection or method call does not exist on the receiver's inferred type.",
    why:
      "Blot records only expose declared fields, arrays expose `.length` (not `.len`), and module functions like `F32.sqrt x` are namespaced rather than implicit receiver methods unless declared as associated functions (`func Vec2.scaled ...`).",
    before: `let n = xs.len`,
    after: `let n = xs.length`,
    checklist: [
      "Use `.length` (not `.len`) on `#[T]` / `Array T`.",
      "Use `.copy` for explicit deep copies and `@storage.push arr item` (or `arr.push item` if imported) for appending.",
      "Check the exact record fields listed in the diagnostic's receiver type.",
    ],
  },
  TYPE_MISMATCH: {
    code: "TYPE_MISMATCH",
    rawCodes: ["type_mismatch"],
    title: "Expression type does not match expected type",
    summary:
      "Two types that must be equal failed unification (for example, returning `F32` where `U32` was declared).",
    why:
      "Blot has strict static typing with zero implicit numeric conversions (`U32` vs `F32` vs `Bool` vs `Unit`), and curried functions apply one argument at a time.",
    before: `entry func main (): U32 => return 1.5`,
    after: `entry func main (): F32 => return 1.5`,
    checklist: [
      "Convert explicitly between `U32` and `F32` with `@u32.to_f32` or `@f32.to_u32` (or `U32.to_f32` / `F32.to_u32`).",
      "Remember curried call syntax: `add a b` passes two curried args, whereas `f (a, b)` passes one 2-tuple.",
      "Write integer literals without decimals (`1`) and float literals with decimals (`1.0`).",
    ],
  },
  SPENT_VALUE: {
    code: "SPENT_VALUE",
    rawCodes: ["spent_value", "use_after_move"],
    title: "Value used after ownership was moved",
    summary:
      "This binding previously transferred ownership of its array/storage to an `own` parameter, `freeze`, or returned record, so reading it again is invalid.",
    why:
      "Blot achieves zero-GC in-place mutation by enforcing single ownership of mutable storage. Once an `own` call takes a binding, the callee may mutate or reallocate its backing memory in place.",
    before: `let a = #[1, 2, 3]
let n = consume a
return n + a.length`,
    after: `let a = #[1, 2, 3]
let n = consume a.copy
return n + a.length`,
    checklist: [
      "Pass `name.copy` at the move site if you need to keep reading `name` afterward.",
      "Or return the owned value from the `own` function and use the returned binding (`let a = update a`).",
      "If the callee only reads the array, remove `own` from its parameter so it borrows instead of moving.",
    ],
  },
  ALIASED_UPDATE: {
    code: "ALIASED_UPDATE",
    rawCodes: ["aliased_update", "borrow_conflict"],
    title: "In-place `:=` or storage mutation on aliased/borrowed value",
    summary:
      "This `:=` index write, `@storage.push`, or `@storage.truncate` mutates storage that another live name, borrow, or caller may still observe.",
    why:
      "Blot's `:=` operator updates array storage in place only when the compiler statically proves unique ownership. Updating through a borrowed parameter or while `let alias = arr` is still used later would expose mutation through an immutable alias.",
    before: `let a = #[1, 2, 3]
let b = a
a[0] := 99
return a[0] + b[0]`,
    after: `let a = #[1, 2, 3]
let b = a.copy
a[0] := 99
return a[0] + b[0]`,
    checklist: [
      "If a local `let b = a` is still read later, snapshot with `let b = a.copy` (or finish reading `b` before mutating `a`).",
      "If `a` is a function parameter, mark it `own` (`func f (a: own #[U32]): #[U32]`) so the caller transfers unique ownership.",
      "Module `const` arrays are deeply immutable; copy them with `let local = pool.copy` before mutating.",
    ],
  },
  OWN_ARGUMENT: {
    code: "OWN_ARGUMENT",
    rawCodes: ["own_argument"],
    title: "Argument to `own` parameter is not uniquely owned",
    summary:
      "A function parameter marked `own` (or `freeze`) requires a fresh value or a local that is not borrowed, aliased, or captured from an outer loop.",
    why:
      "An `own` callee is allowed to mutate or consume the argument's backing storage in place, so the caller cannot still share that storage with another binding or outer loop iteration.",
    before: `func bad (xs: #[U32]): #[U32] => return consume_and_grow xs`,
    after: `func good (xs: own #[U32]): #[U32] => return consume_and_grow xs`,
    checklist: [
      "Mark the enclosing function's parameter `own` if it should transfer ownership through.",
      "Or pass `xs.copy` to give the callee a fresh owned copy.",
      "Do not move a loop-invariant outer binding into an `own` call inside a loop; copy it or thread it via rebinding.",
    ],
  },
  RESULT_NOT_OWNED: {
    code: "RESULT_NOT_OWNED",
    rawCodes: ["result_not_owned"],
    title: "Function must return a uniquely owned value",
    summary:
      "A non-entry function returning array/storage data must return a fresh allocation or a uniquely owned local/parameter, not a borrowed or aliased value.",
    why:
      "Callers rely on receiving an owned value they can safely mutate or return further without dangling borrows.",
    before: `func pick (xs: #[U32]): #[U32] => return xs`,
    after: `func pick (xs: own #[U32]): #[U32] => return xs
// or: func pick (xs: #[U32]): #[U32] => return xs.copy`,
    checklist: [
      "Return `value.copy` to hand the caller a fresh owned copy.",
      "Or mark the source parameter `own` if ownership should pass through zero-copy.",
      "Ensure no other live alias/borrow of the returned local remains.",
    ],
  },
  ENTRY_TYPE: {
    code: "ENTRY_TYPE",
    rawCodes: ["entry_type"],
    title:
      "Entry function has unhandled effects or invalid ABI-8 boundary type",
    summary:
      "An `entry func`, `entry kernel`, or `entry process` cannot leave algebraic effects unhandled or expose closures/internal handles directly across the Wasm ABI-8 boundary.",
    why:
      "The WebAssembly host boundary has no ambient effect handlers or GC object references. Every effect used inside an entry point must be handled lexically with `with ...:` or `do <provider>:`.",
    before: `type Clock is effect = { now: Unit -> U32 }
entry func main (): U32 =>
  use t <- Clock.now ()
  return t`,
    after: `type Clock is effect = { now: Unit -> U32 }
entry func main (): U32 =>
  with Clock = { now: func () => return 42 }:
    use t <- Clock.now ()
    return t`,
    checklist: [
      "Handle every effect reported in `(unhandled: Effect.op)` with `with Effect = { op: func ... => ... }:` or `do provider:`.",
      "Keep entry parameter and return types to ABI-8 data: scalars (`U32`, `F32`, `Bool`, `Unit`), records, sums, tuples, and arrays (`#[T]`).",
    ],
  },
  EFFECT_MISMATCH: {
    code: "EFFECT_MISMATCH",
    rawCodes: [
      "effect_mismatch",
      "const_effect",
      "let_effect",
      "spark_effectful",
      "kernel_effectful",
    ],
    title:
      "Effectful computation used where pure code or a different effect row is required",
    summary:
      "An expression performs an algebraic effect that is not permitted in this pure context (`const`, `let`, `spark`, `entry kernel`, or pure function signature).",
    why:
      "Blot functions, `const` definitions, `spark` SIMD comprehensions, and `entry kernel` workers are pure by default. Effectful calls must be bound with `use x <- ...` inside an effectful scope or handled locally with `with` / `do`.",
    before: `let t = Clock.now ()`,
    after: `use t <- Clock.now ()`,
    checklist: [
      "Use `use x <- effect_call` (not `let x = ...`) to invoke effectful operations.",
      "Keep `spark #[...]` bodies and `entry kernel` functions completely pure.",
      "Handle local effects with `with Effect = { ... }:` or `do provider:` before crossing a pure boundary.",
    ],
  },
  NON_EXHAUSTIVE_MATCH: {
    code: "NON_EXHAUSTIVE_MATCH",
    rawCodes: ["non_exhaustive_match", "refutable_pattern"],
    title: "Pattern match does not cover every possible variant",
    summary:
      "A `case ... of` expression or `let` destructuring misses one or more constructors of the matched algebraic data type.",
    why:
      "Blot requires exhaustive matches so runtime match failures cannot occur silently.",
    before: `let $Some value = opt`,
    after: `let $Some value = opt else:
  return 0`,
    checklist: [
      "Add arms for every variant in `case x of`, or add a catch-all `_ => ...` arm.",
      "For single-variant destructuring in a `let`, attach an `else:` fallback suite that exits (`return` or `break`).",
    ],
  },
  FUNCTION_RETURN_REQUIRED: {
    code: "FUNCTION_RETURN_REQUIRED",
    rawCodes: [
      "function_return_required",
      "invalid_return",
      "return_outside_function",
    ],
    title: "Block-bodied function is missing an explicit `return`",
    summary:
      "Every control-flow path through an indented function body must finish with an explicit `return <expr>`.",
    why:
      "Single-expression functions (`func x => x + 1`) return implicitly, but indented block suites require explicit `return` on every branch so control flow stays unambiguous.",
    before: `func clamp (x: U32): U32 =>
  if x > 10:
    return 10
  x`,
    after: `func clamp (x: U32): U32 =>
  if x > 10:
    return 10
  return x`,
    checklist: [
      "End every branch of an indented function body with `return <value>`.",
      "Or use single-expression form `func x => expr` when no statements are needed.",
      "Inside `do:` blocks, use `break <value>` to yield a value from the block.",
    ],
  },
  DUPLICATE_NAME: {
    code: "DUPLICATE_NAME",
    rawCodes: [
      "duplicate_name",
      "duplicate_field",
      "duplicate_record_field",
      "duplicate_pattern_binding",
    ],
    title: "Name declared more than once in the same scope",
    summary:
      "Two top-level declarations, record fields, or pattern bindings share the same identifier.",
    why:
      "Module declarations and record fields must have distinct names. Local variables can be updated with `:=` rather than re-declaring conflicting bindings in the same pattern.",
    before: `let x = 1
// updating a local:
let x = 2 // ok in suites, but duplicate top-level const/func is rejected`,
    after: `// Use unique top-level names, or rebind locals with :=
let x = 1
x := 2`,
    checklist: [
      "Rename one of the duplicate top-level `func` / `const` / `type` declarations.",
      "To update an existing local variable in place, use `x := new_value` (or `x := self + 1`).",
    ],
  },
  UNKNOWN_REBINDING: {
    code: "UNKNOWN_REBINDING",
    rawCodes: ["unknown_rebinding"],
    title: "Rebinding target `:=` is not a local variable in scope",
    summary:
      "The left-hand side of `:=` is not a mutable local binding in the current function scope.",
    why:
      "Only local `let` bindings and parameters can be updated with `:=`. Module-level `const` bindings are immutable.",
    before: `const count = 0
entry func main (): U32 =>
  count := 1
  return count`,
    after: `entry func main (): U32 =>
  let count = 0
  count := 1
  return count`,
    checklist: [
      "Introduce local state with `let name = initial` before updating with `name := next`.",
      "For persistent cross-turn state, use `entry process` instead of mutable module globals.",
    ],
  },
};

const RAW_TO_ENTRY = new Map<string, DiagnosticExplanationEntry>();
for (const entry of Object.values(DIAGNOSTIC_CATALOG)) {
  RAW_TO_ENTRY.set(entry.code.toLowerCase(), entry);
  for (const raw of entry.rawCodes) {
    RAW_TO_ENTRY.set(raw.toLowerCase(), entry);
  }
}

export function lookupDiagnosticExplanation(
  code: string,
): DiagnosticExplanationEntry | undefined {
  const direct = RAW_TO_ENTRY.get(code.trim().toLowerCase());
  if (direct) return direct;
  const canonical = canonicalDiagnosticCode(code);
  return DIAGNOSTIC_CATALOG[canonical];
}

export function formatExplanation(code: string): string | null {
  const entry = lookupDiagnosticExplanation(code);
  if (!entry) return null;
  const lines: string[] = [
    `[${entry.code}] ${entry.title}`,
    "",
    entry.summary,
    "",
    `Why: ${entry.why}`,
    "",
    "Before (fails):",
    ...entry.before.split("\n").map((l) => `  ${l}`),
    "",
    "After (fixed):",
    ...entry.after.split("\n").map((l) => `  ${l}`),
    "",
    "Checklist:",
    ...entry.checklist.map((item) => `  - ${item}`),
    "",
    `Reference: skills/blot-diagnostics/SKILL.md#${entry.code}`,
  ];
  return lines.join("\n");
}

export function formatDiagnosticCodeList(): string {
  const entries = Object.values(DIAGNOSTIC_CATALOG);
  const pad = Math.max(...entries.map((e) => e.code.length));
  const rows = entries.map((e) => `  ${e.code.padEnd(pad)}  ${e.title}`);
  return [
    "Blot diagnostic codes (run `blot explain <CODE>` for full details):",
    "",
    ...rows,
    "",
    "Handbook: skills/blot-diagnostics/SKILL.md",
  ].join("\n");
}

function buildLineIndex(source: string): LineIndex {
  const bytes = textEncoder.encode(source);
  const lineStarts: number[] = [0];
  for (let i = 0; i < bytes.length; i++) {
    if (bytes[i] === 0x0a) {
      lineStarts.push(i + 1);
    }
  }
  const lines = source.split("\n").map((line) =>
    line.endsWith("\r") ? line.slice(0, -1) : line
  );
  return { bytes, lineStarts, lines };
}

function clampByte(index: LineIndex, offset: number): number {
  if (!Number.isFinite(offset) || offset < 0) return 0;
  if (offset > index.bytes.length) return index.bytes.length;
  return offset;
}

function byteOffsetToLineCol(index: LineIndex, byteOffset: number): LineCol {
  const clamped = clampByte(index, byteOffset);
  let lo = 0;
  let hi = index.lineStarts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (index.lineStarts[mid] <= clamped) lo = mid;
    else hi = mid - 1;
  }
  const lineStart = index.lineStarts[lo];
  const prefix = textDecoder.decode(index.bytes.subarray(lineStart, clamped));
  const col = [...prefix].length + 1;
  return { line: lo + 1, col };
}

function sliceUtf8(index: LineIndex, start: number, end: number): string {
  const s = clampByte(index, start);
  const e = clampByte(index, Math.max(s, end));
  return textDecoder.decode(index.bytes.subarray(s, e));
}

function expandPointSpan(
  index: LineIndex,
  start: number,
  end: number,
): [number, number] {
  const s = clampByte(index, start);
  const e = clampByte(index, end);
  if (e > s) return [s, e];
  if (s >= index.bytes.length) return [s, s];
  const isIdentByte = (b: number) =>
    (b >= 0x30 && b <= 0x39) ||
    (b >= 0x41 && b <= 0x5a) ||
    (b >= 0x61 && b <= 0x7a) ||
    b === 0x5f || b === 0x24 || b === 0x40;
  let cursor = s;
  if (isIdentByte(index.bytes[cursor])) {
    while (cursor < index.bytes.length) {
      if (isIdentByte(index.bytes[cursor])) {
        cursor++;
      } else if (
        index.bytes[cursor] === 0x2e &&
        cursor + 1 < index.bytes.length &&
        isIdentByte(index.bytes[cursor + 1])
      ) {
        cursor++;
      } else {
        break;
      }
    }
    return [s, cursor];
  }
  if (index.bytes[cursor] !== 0x0a && index.bytes[cursor] !== 0x0d) {
    return [s, Math.min(index.bytes.length, s + 1)];
  }
  return [s, s];
}

function findEnclosingScope(
  index: LineIndex,
  line1Based: number,
): string | null {
  const declRe =
    /^(?:private\s+)?(entry\s+(?:func|kernel|process|const|let)|func|const|let|type|impl|contract|effect)\s+([A-Za-z_][A-Za-z0-9_.]*)/;
  for (let i = Math.min(line1Based - 1, index.lines.length - 1); i >= 0; i--) {
    const line = index.lines[i];
    if (!line || line.startsWith(" ") || line.startsWith("\t")) continue;
    const match = declRe.exec(line);
    if (match) {
      return `${match[1].replace(/\s+/g, " ")} ${match[2]}`;
    }
  }
  return null;
}

function extractBindingIdent(rawText: string): string {
  const trimmed = rawText.trim();
  const m = /^\(?\s*(?:own\s+)?([A-Za-z_][A-Za-z0-9_]*)/.exec(trimmed);
  return m ? m[1] : trimmed;
}

function formatOwnParameterSuggestion(
  rawSubject: string,
  name: string,
): string {
  const m = /^\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^)]+)\)$/.exec(
    rawSubject.trim(),
  );
  if (m) {
    const ty = m[2].trim();
    return `(${m[1]}: own ${ty})`;
  }
  return `(${name}: own #[T])`;
}

function extractRecordFields(operand: string): string[] {
  const m = /^\{\s*([^}]+)\s*\}$/.exec(operand.trim());
  if (!m) return [];
  return m[1]
    .split(",")
    .map((part) => part.split(":")[0]?.trim() ?? "")
    .filter((name) => /^[A-Za-z_][A-Za-z0-9_]*$/.test(name));
}

function formatExcerpt(
  index: LineIndex,
  spans: AnnotatedSpan[],
): string[] {
  if (spans.length === 0 || index.lines.length === 0) return [];
  const located = spans.map((span) => {
    const [s, e] = expandPointSpan(index, span.startByte, span.endByte);
    const startPos = byteOffsetToLineCol(index, s);
    const endPos = byteOffsetToLineCol(index, Math.max(s, e - 1));
    const endColOnStartLine = endPos.line === startPos.line
      ? endPos.col
      : [...(index.lines[startPos.line - 1] ?? "")].length;
    const width = Math.max(1, endColOnStartLine - startPos.col + 1);
    return {
      line: startPos.line,
      col: startPos.col,
      width,
      marker: span.marker,
      label: span.label,
    };
  });

  // Sort spans by line then column; primary last if same line so it stands out.
  located.sort((a, b) =>
    a.line !== b.line
      ? a.line - b.line
      : a.marker !== b.marker
      ? (a.marker === "-" ? -1 : 1)
      : a.col - b.col
  );

  const lineSet = new Set<number>();
  for (const item of located) {
    lineSet.add(item.line);
  }
  const sortedLines = [...lineSet].sort((a, b) => a - b);
  const displayLines: number[] = [];
  for (let i = 0; i < sortedLines.length; i++) {
    const ln = sortedLines[i];
    if (i > 0) {
      const prev = sortedLines[i - 1];
      if (ln - prev <= 3) {
        for (let k = prev + 1; k < ln; k++) displayLines.push(k);
      }
    }
    displayLines.push(ln);
  }

  const maxLineNum = Math.max(...displayLines);
  const gutterWidth = Math.max(2, String(maxLineNum).length);
  const blankGutter = " ".repeat(gutterWidth);
  const out: string[] = [];

  for (let i = 0; i < displayLines.length; i++) {
    const ln = displayLines[i];
    if (i > 0 && ln - displayLines[i - 1] > 1) {
      out.push(`${blankGutter} ...`);
    }
    const lineText = index.lines[ln - 1] ?? "";
    out.push(`${String(ln).padStart(gutterWidth)} | ${lineText}`);
    for (const item of located) {
      if (item.line !== ln) continue;
      const pad = " ".repeat(Math.max(0, item.col - 1));
      const carets = item.marker.repeat(item.width);
      const suffix = item.label ? ` ${item.label}` : "";
      out.push(`${blankGutter} | ${pad}${carets}${suffix}`);
    }
  }
  return out;
}

interface ParsedSyntaxDetail {
  detailSpan?: RawSpan;
  expectedToken?: string | null;
  actualToken?: string | null;
}

function getSyntaxDetail(record: RawDiagnosticRecord): ParsedSyntaxDetail {
  const out: ParsedSyntaxDetail = {
    expectedToken: record.expected_token,
    actualToken: record.actual_token,
  };
  if (Array.isArray(record.details) && record.details.length > 0) {
    const first = record.details[0];
    if (first.detail_span && first.detail_span.end > first.detail_span.start) {
      out.detailSpan = first.detail_span;
    } else if (
      typeof first.start === "number" &&
      typeof first.end === "number" &&
      (first.start !== record.start || first.end !== record.end)
    ) {
      out.detailSpan = { start: first.start, end: first.end };
    }
    if (!out.expectedToken && first.expected_token) {
      out.expectedToken = first.expected_token;
    }
    if (!out.actualToken && first.actual_token) {
      out.actualToken = first.actual_token;
    }
  }
  return out;
}

function getDispatchExplanation(
  record: RawDiagnosticRecord,
): RawDispatchExplanation | null {
  if (
    record.details && !Array.isArray(record.details) &&
    record.details.explanation
  ) {
    return record.details.explanation;
  }
  return null;
}

function getDiagnosticContexts(
  record: RawDiagnosticRecord,
): RawDiagnosticContext[] {
  if (
    record.details && !Array.isArray(record.details) &&
    Array.isArray(record.details.contexts)
  ) {
    return record.details.contexts;
  }
  return [];
}

function buildHeadlineAndFix(
  canonical: string,
  record: RawDiagnosticRecord,
  index: LineIndex | null,
  subjectName: string,
  subjectRaw: string,
  holderName: string,
  originLine: number | null,
): { headline: string; primaryLabel: string; fix: string | null } {
  const snippet = index
    ? sliceUtf8(index, ...expandPointSpan(index, record.start, record.end))
      .trim()
    : "";
  const primaryLineText = index
    ? (index.lines[byteOffsetToLineCol(index, record.start).line - 1] ?? "")
    : "";
  const trimmedLine = primaryLineText.trim();

  if (canonical === "SYNTAX_ERROR" || canonical === "UNMATCHED_DELIMITER") {
    const syn = getSyntaxDetail(record);
    let fix: string | null = null;
    if (/^fn\b/.test(trimmedLine) || snippet === "fn") {
      fix =
        "Blot uses `func`, not `fn` (e.g. `func add (a: U32) -> (b: U32): U32 => return a + b`).";
    } else if (/^type\s+[A-Z][A-Za-z0-9_]*\s*=.*\|/.test(trimmedLine)) {
      fix =
        "Sum types require `is data` and `$`-prefixed constructors: `type Opt is data = $Some U32 | $Nothing`.";
    } else if (/^type\s+[A-Z][A-Za-z0-9_]*\s*=\s*\$/.test(trimmedLine)) {
      fix =
        "Algebraic data types require `is data`: `type Opt is data = $Some U32 | $Nothing`.";
    } else if (
      /^(?:entry\s+|private\s+)?func\b.*->\s*[A-Z][A-Za-z0-9_]*\s*(?:=>|:|$)/
        .test(trimmedLine) && !trimmedLine.includes("): ")
    ) {
      fix =
        "Write the return type after `:` before `=>` (`func f (x: U32): U32 => ...`); `->` separates curried parameters.";
    } else if (
      trimmedLine.includes("{") &&
      /^(?:entry\s+|private\s+)?(?:func|if|for|while|else)\b/.test(trimmedLine)
    ) {
      fix =
        "Blot uses indented suites after `=>` or `:`, not `{ ... }` braces.";
    } else if (trimmedLine.includes("&&") || trimmedLine.includes("||")) {
      fix =
        "Blot uses `and`, `or`, and `not` (not `&&`, `||`, `!`) for boolean operators.";
    } else if (/^(?:mut|var)\s+/.test(trimmedLine)) {
      fix =
        "Blot declares locals with `let x = ...` and updates them with `x := ...` (no `mut`/`var` keyword).";
    } else if (syn.expectedToken && syn.actualToken) {
      fix =
        `Expected ${syn.expectedToken}, found ${syn.actualToken}. Check indentation, \`=>\`, and \`:\` suite headers.`;
    } else if (syn.actualToken) {
      fix =
        `Unexpected token \`${syn.actualToken}\`. Check Blot syntax (see \`blot guide --cheatsheet\`).`;
    } else {
      fix =
        "Check Blot declaration and suite syntax (`blot guide --cheatsheet`).";
    }
    const primaryLabel = syn.expectedToken
      ? `expected ${syn.expectedToken}`
      : syn.actualToken
      ? `unexpected ${syn.actualToken}`
      : "syntax error here";
    return { headline: record.message, primaryLabel, fix };
  }

  if (canonical === "UNSUPPORTED_EXPRESSION") {
    const isBareList = record.message.includes("`[...]`") ||
      (snippet.startsWith("[") && !snippet.startsWith("#["));
    return {
      headline: record.message,
      primaryLabel: isBareList ? "use `#[...]` here" : "unsupported expression",
      fix: isBareList
        ? "Replace bare `[...]` with `#[...]` for Blot array literals (e.g. `#[1, 2, 3]`)."
        : "Replace this expression with a supported Blot vNext form (`blot guide --cheatsheet`).",
    };
  }

  if (canonical === "UNKNOWN_VALUE") {
    const ctorMatch = /did you mean `(\$[A-Za-z0-9_]+)`\?/.exec(record.message);
    if (ctorMatch) {
      return {
        headline: record.message,
        primaryLabel: `add \`$\` -> \`${ctorMatch[1]}\``,
        fix: `Prefix the data constructor with \`$\`: use \`${
          ctorMatch[1]
        }\` instead of \`${snippet || ctorMatch[1].slice(1)}\`.`,
      };
    }
    const typoMatch = /did you mean `([^`]+)`\?/.exec(record.message);
    if (typoMatch) {
      return {
        headline: record.message,
        primaryLabel: `did you mean \`${typoMatch[1]}\`?`,
        fix: `Replace \`${snippet || "this name"}\` with \`${typoMatch[1]}\`.`,
      };
    }
    if (snippet === "None") {
      return {
        headline: "Unknown value `None`.",
        primaryLabel: "not in scope",
        fix:
          "Blot's prelude option constructors are `$Nothing` and `$Some x` (not `None`/`Some`).",
      };
    }
    if (snippet === "String" || snippet === "str") {
      return {
        headline: `Unknown value \`${snippet}\`.`,
        primaryLabel: "not in scope",
        fix: "Blot represents strings as byte arrays (`#[U8]` / `Array U8`).",
      };
    }
    if (
      ["Int", "i32", "u32", "f32", "float", "bool", "int"].includes(snippet)
    ) {
      return {
        headline: `Unknown value \`${snippet}\`.`,
        primaryLabel: "not in scope",
        fix:
          "Blot's built-in scalar types are `U32`, `F32`, `Bool`, and `Unit` (capitalized).",
      };
    }
    return {
      headline: record.message,
      primaryLabel: "not in scope",
      fix:
        "Check spelling, add a leading `$` for data constructors (`$Some`), or import the defining module.",
    };
  }

  if (canonical === "MISSING_MEMBER") {
    const exp = getDispatchExplanation(record);
    const member = exp?.member ??
      (snippet.includes(".")
        ? snippet.slice(snippet.lastIndexOf(".") + 1)
        : "");
    const receiverType = exp?.candidates?.[0]?.operand ?? "";
    const fields = receiverType ? extractRecordFields(receiverType) : [];
    const headline = member && receiverType
      ? `Type \`${receiverType}\` has no field or member \`.${member}\`.`
      : member
      ? `Receiver has no field or member \`.${member}\`.`
      : record.message;
    let fix: string;
    if (member === "len") {
      fix = "Blot arrays use `.length` (not `.len`).";
    } else if (member === "push") {
      fix =
        "Use `@storage.push arr item` (or `arr.push item` if an array extension is in scope) to append to an owned `#[T]`.";
    } else if (fields.length > 0) {
      fix = `Available fields on \`${receiverType}\`: ${
        fields.map((f) => `\`${f}\``).join(", ")
      }.`;
    } else {
      fix =
        "Check the receiver's fields or call a namespaced function directly (e.g. `F32.sqrt x`).";
    }
    return {
      headline,
      primaryLabel: member ? `unknown member \`.${member}\`` : "missing member",
      fix,
    };
  }

  if (canonical === "TYPE_MISMATCH") {
    const numericPair = record.message.includes("F32") &&
      record.message.includes("U32");
    const fix = numericPair
      ? "Blot has no implicit numeric conversions; match the literal (`1` vs `1.0`) or convert explicitly with `@u32.to_f32` / `@f32.to_u32`."
      : "Align the expression type with the declared annotation or expected parameter type.";
    return {
      headline: record.message,
      primaryLabel: "type mismatch here",
      fix,
    };
  }

  if (canonical === "SPENT_VALUE") {
    const name = subjectName || extractBindingIdent(snippet) || "this value";
    const copyExpr = subjectName ? `${subjectName}.copy` : "value.copy";
    const where = originLine ? ` at line ${originLine}` : "";
    return {
      headline:
        `\`${name}\` was already moved${where} and can no longer be used here.`,
      primaryLabel: `\`${name}\` used after move`,
      fix:
        `Pass \`${copyExpr}\`${where} to keep \`${name}\` live, or use the owned value returned by that call.`,
    };
  }

  if (canonical === "ALIASED_UPDATE") {
    const name = subjectName || extractBindingIdent(snippet) || "this value";
    const copyExpr = subjectName ? `${subjectName}.copy` : "value.copy";
    if (record.origin_kind === "borrowed") {
      const holder = holderName || "another binding";
      const where = originLine ? ` (line ${originLine})` : "";
      return {
        headline:
          `Cannot mutate \`${name}\` in place while \`${holder}\` still borrows it.`,
        primaryLabel: "mutated while borrowed",
        fix: holderName
          ? `Snapshot with \`let ${holderName} = ${copyExpr}\`${where}, or finish reading \`${holderName}\` before mutating \`${name}\`.`
          : `Take \`${copyExpr}\` before creating the alias, or end the borrow before mutating \`${name}\`.`,
      };
    }
    if (record.origin_kind === "parameter") {
      const ownParam = formatOwnParameterSuggestion(subjectRaw, name);
      return {
        headline:
          `Cannot mutate borrowed parameter \`${name}\` in place without \`own\`.`,
        primaryLabel: "mutates borrowed parameter",
        fix:
          `Mark the parameter \`own\` (e.g. \`${ownParam}\`) to mutate in place, or copy locally with \`let local = ${copyExpr}\`.`,
      };
    }
    return {
      headline:
        `Cannot mutate \`${name}\` in place because another alias may still observe it.`,
      primaryLabel: "aliased in-place write",
      fix:
        `Take an explicit copy (\`let local = ${copyExpr}\`) before updating with \`:=\`, or remove the earlier alias.`,
    };
  }

  if (canonical === "OWN_ARGUMENT") {
    const name = subjectName || extractBindingIdent(snippet) || "this argument";
    const copyExpr = subjectName ? `${subjectName}.copy` : "value.copy";
    const fix = record.origin_kind === "parameter"
      ? `Mark parameter \`${name}\` as \`own\` to forward ownership, or pass \`${copyExpr}\`.`
      : `Pass \`${copyExpr}\` to give the callee a fresh owned copy, or end live borrows of \`${name}\` first.`;
    return {
      headline:
        `Argument \`${name}\` is not uniquely owned and cannot be moved into an \`own\` parameter.`,
      primaryLabel: "not uniquely owned",
      fix,
    };
  }

  if (canonical === "RESULT_NOT_OWNED") {
    const name = subjectName || extractBindingIdent(snippet) || "this value";
    const copyExpr = subjectName ? `${subjectName}.copy` : "value.copy";
    return {
      headline:
        `Function result \`${name}\` is borrowed or aliased; returned storage must be uniquely owned.`,
      primaryLabel: "borrowed result cannot escape",
      fix:
        `Return \`${copyExpr}\` to hand the caller a fresh copy, or take the source parameter with \`own\`.`,
    };
  }

  if (canonical === "ENTRY_TYPE") {
    const effMatch = /\(unhandled:\s*([^)]+)\)/.exec(record.message);
    if (effMatch) {
      const op = effMatch[1].trim();
      const family = op.includes(".") ? op.split(".")[0] : op;
      const member = op.includes(".") ? op.split(".")[1] : "op";
      return {
        headline:
          `Entry function leaves effect \`${op}\` unhandled across the Wasm boundary.`,
        primaryLabel: `unhandled effect \`${op}\``,
        fix:
          `Handle \`${op}\` inside the entry function with \`with ${family} = { ${member}: func ... => ... }:\` or \`do <provider>:\`.`,
      };
    }
    return {
      headline: record.message,
      primaryLabel: "invalid entry signature",
      fix:
        "Ensure entry functions handle all effects and use ABI-8 boundary types (scalars, records, sums, arrays).",
    };
  }

  if (
    canonical === "NON_EXHAUSTIVE_MATCH" || canonical === "REFUTABLE_PATTERN"
  ) {
    return {
      headline: record.message,
      primaryLabel: "non-exhaustive pattern",
      fix:
        "Handle every variant in `case ... of` (or add `_ => ...`), or attach an `else:` suite to a refutable `let`.",
    };
  }

  if (canonical === "FUNCTION_RETURN_REQUIRED") {
    return {
      headline: record.message,
      primaryLabel: "missing explicit `return`",
      fix:
        "End every path in an indented function body with `return <expr>` (or use single-expression `func x => expr`).",
    };
  }

  if (
    canonical === "EFFECT_MISMATCH" || canonical === "CONST_EFFECT" ||
    canonical === "LET_EFFECT"
  ) {
    return {
      headline: record.message,
      primaryLabel: "effect not allowed here",
      fix:
        "Bind effectful calls with `use x <- ...` inside an effectful scope, or handle the effect locally with `with ...:` / `do <provider>:`.",
    };
  }

  const catalogEntry = lookupDiagnosticExplanation(canonical);
  return {
    headline: record.message,
    primaryLabel: canonical.toLowerCase().replace(/_/g, " "),
    fix: catalogEntry ? catalogEntry.checklist[0] ?? null : null,
  };
}

export function formatDiagnostic(
  record: RawDiagnosticRecord,
  options: FormatDiagnosticOptions = {},
): string {
  const canonical = canonicalDiagnosticCode(record.code);
  const file = options.displayFilename ?? record.filename ?? "<input>";
  const index = typeof options.source === "string"
    ? buildLineIndex(options.source)
    : null;

  const subjectRaw = index && record.subject_end &&
      record.subject_end > (record.subject_start ?? 0)
    ? sliceUtf8(index, record.subject_start ?? 0, record.subject_end)
    : "";
  const subjectName = subjectRaw ? extractBindingIdent(subjectRaw) : "";
  const holderName = index && record.holder_end &&
      record.holder_end > (record.holder_start ?? 0)
    ? extractBindingIdent(
      sliceUtf8(index, record.holder_start ?? 0, record.holder_end),
    )
    : "";

  const hasOrigin = Boolean(
    index && record.origin_kind && record.origin_end &&
      record.origin_end > (record.origin_start ?? 0),
  );
  const originLine = hasOrigin && index
    ? byteOffsetToLineCol(index, record.origin_start ?? 0).line
    : null;

  const { headline, primaryLabel, fix } = buildHeadlineAndFix(
    canonical,
    record,
    index,
    subjectName,
    subjectRaw,
    holderName,
    originLine,
  );

  const out: string[] = [`[${canonical}] ${headline}`];

  if (index) {
    const pos = byteOffsetToLineCol(index, record.start);
    const scope = findEnclosingScope(index, pos.line);
    const base = basename(file);
    out.push(scope ? `in ${base} › ${scope}` : `in ${base}`);
    out.push(`at ${file}:${pos.line}:${pos.col}`);

    const spans: AnnotatedSpan[] = [];

    // Secondary blame span from uniqueness origins
    if (
      hasOrigin && record.origin_start !== undefined &&
      record.origin_end !== undefined
    ) {
      let originLabel = "related here";
      if (record.origin_kind === "moved") {
        originLabel = subjectName
          ? `\`${subjectName}\` moved here`
          : "moved here";
      } else if (record.origin_kind === "borrowed") {
        originLabel = holderName
          ? `borrowed by \`${holderName}\` here`
          : "borrowed here";
      } else if (record.origin_kind === "aliased") {
        originLabel = "aliased here";
      } else if (record.origin_kind === "parameter") {
        originLabel = "borrowed parameter (not `own`)";
      }
      spans.push({
        startByte: record.origin_start,
        endByte: record.origin_end,
        marker: "-",
        label: originLabel,
      });
    } else {
      // Secondary span from syntax detail (e.g. exact unexpected token inside declaration)
      const syn = getSyntaxDetail(record);
      if (
        syn.detailSpan &&
        (syn.detailSpan.start !== record.start ||
          syn.detailSpan.end !== record.end)
      ) {
        const synLabel = syn.actualToken
          ? `unexpected ${syn.actualToken} here`
          : "failed here";
        spans.push({
          startByte: syn.detailSpan.start,
          endByte: syn.detailSpan.end,
          marker: "-",
          label: synLabel,
        });
      }
      // Secondary context spans from check-project
      for (const ctx of getDiagnosticContexts(record)) {
        if (ctx.span && ctx.span.end > ctx.span.start) {
          spans.push({
            startByte: ctx.span.start,
            endByte: ctx.span.end,
            marker: "-",
            label: ctx.message ?? ctx.kind ?? "related context",
          });
        }
      }
    }

    spans.push({
      startByte: record.start,
      endByte: record.end,
      marker: "^",
      label: primaryLabel,
    });

    out.push(...formatExcerpt(index, spans));
  } else {
    out.push(`at ${file}:${record.start}-${record.end}`);
  }

  if (fix) {
    out.push(`fix: ${fix}`);
  }
  const hasDoc = Boolean(lookupDiagnosticExplanation(canonical));
  if (hasDoc) {
    out.push(
      `doc: blot explain ${canonical} (skills/blot-diagnostics/SKILL.md#${canonical})`,
    );
  } else {
    out.push("doc: blot explain --list (CHEATSHEET.md)");
  }

  return out.join("\n");
}

export async function formatDiagnosticReport(
  records: RawDiagnosticRecord[],
  readSource: (path: string) => Promise<string | undefined> = async (path) => {
    try {
      return await Deno.readTextFile(path);
    } catch {
      return undefined;
    }
  },
): Promise<string> {
  const cache = new Map<string, string | undefined>();
  const rendered: string[] = [];
  for (const record of records) {
    let source: string | undefined;
    if (record.filename) {
      if (!cache.has(record.filename)) {
        cache.set(record.filename, await readSource(record.filename));
      }
      source = cache.get(record.filename);
    }
    rendered.push(formatDiagnostic(record, { source }));
  }
  return rendered.join("\n\n");
}

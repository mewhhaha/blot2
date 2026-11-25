import { basename } from "node:path";

export const DIAGNOSTIC_SCHEMA_VERSION = 1;

export interface Stage0Provenance {
  readonly stage: "stage0";
  readonly phase: "compile" | "execute" | "result" | "generated_source";
  readonly module: string;
  readonly input: string;
  readonly generator?: string;
}

export interface RawSpan {
  start: number;
  end: number;
}

export interface RawRelatedLocation {
  filename: string;
  start: number;
  end: number;
  offset_encoding?: string;
}

export interface RawDispatchCandidate {
  side?: string | null;
  operand?: string | null;
  outcome?: string | null;
  method?: string | null;
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
  filename?: string;
  start?: number;
  end?: number;
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
  origin_kind?: string;
  origin_start?: number;
  origin_end?: number;
  subject_start?: number;
  subject_end?: number;
  holder_start?: number;
  holder_end?: number;
}

export interface DiagnosticQuickFix {
  title: string;
  startByte: number;
  endByte: number;
  newText: string;
  complete?: boolean;
}

export interface EnrichedDiagnosticSpan {
  filename?: string;
  startByte: number;
  endByte: number;
  line?: number;
  col?: number;
  endLine?: number;
  endCol?: number;
  label: string;
}

export interface AnalyzedDiagnostic {
  canonicalCode: string;
  headline: string;
  primarySpan: { startByte: number; endByte: number; label: string };
  secondarySpan:
    | { startByte: number; endByte: number; label: string }
    | null;
  fix: string | null;
  docRef: string;
  quickFixes: DiagnosticQuickFix[];
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
  blame?: {
    kind: string;
    start: number;
    end: number;
    subjectStart: number;
    subjectEnd: number;
    holderStart: number;
    holderEnd: number;
  };
  explanation?: RawDispatchExplanation;
  contexts?: RawDiagnosticContext[];
  provenance?: Stage0Provenance;
  virtual_source?: string;
  related?: RawRelatedLocation | null;
}

export interface EnrichedDiagnostic
  extends Omit<RawDiagnosticRecord, "related"> {
  kind: "diagnostic";
  schemaVersion: typeof DIAGNOSTIC_SCHEMA_VERSION;
  severity: "error";
  canonicalCode: string;
  rawCode: string;
  headline: string;
  scope: string | null;
  primarySpan: EnrichedDiagnosticSpan;
  related: EnrichedDiagnosticSpan[];
  fix: string | null;
  quickFixes: DiagnosticQuickFix[];
  docRef: string;
  provenance?: Stage0Provenance;
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
  relatedSources?: Readonly<Record<string, string | undefined>>;
}

export interface EnrichDiagnosticOptions {
  source?: string;
  relatedSources?: Readonly<Record<string, string | undefined>>;
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

const SURFACE_TOKEN_MAP: Record<string, string> = {
  eof: "end of file",
  identifier: "an identifier",
  type_identifier: "a type name",
  integer: "an integer literal",
  float: "a float literal",
  string: "a string literal",
  intrinsic: "an intrinsic",
  symbol: "an operator",
  comment: "a comment",
  l_paren: "'('",
  r_paren: "')'",
  l_bracket: "'['",
  r_bracket: "']'",
  l_brace: "'{'",
  r_brace: "'}'",
  comma: "','",
  dot: "'.'",
  selector: "a field selector",
  dot_dot: "'..'",
  colon: "':'",
  colon_equal: "':='",
  arrow: "'->'",
  fat_arrow: "'=>'",
  left_arrow: "'<-'",
  hash: "'#'",
  at: "'@'",
  ellipsis: "'...'",
  backtick: "'`'",
  dollar: "'$'",
  star: "'*'",
  caret: "'^'",
  pipe: "'|'",
  bang: "'!'",
  equal: "'='",
  kw_import: "'import'",
  kw_as: "'as'",
  kw_const: "'const'",
  kw_let: "'let'",
  kw_type: "'type'",
  kw_is: "'is'",
  kw_data: "'data'",
  kw_effect: "'effect'",
  kw_infixl: "'infixl'",
  kw_infixr: "'infixr'",
  kw_infix: "'infix'",
  kw_func: "'func'",
  kw_if: "'if'",
  kw_then: "'then'",
  kw_else: "'else'",
  kw_do: "'do'",
  kw_case: "'case'",
  kw_of: "'of'",
  kw_for: "'for'",
  kw_in: "'in'",
  kw_ever: "'ever'",
  kw_use: "'use'",
  kw_return: "'return'",
  kw_yield: "'yield'",
  kw_break: "'break'",
  kw_continue: "'continue'",
  kw_complete: "'complete'",
  kw_true: "'true'",
  kw_false: "'false'",
  kw_and: "'and'",
  kw_or: "'or'",
  kw_from: "'from'",
  kw_where: "'where'",
  private_from: "'from'",
  private_where: "'where'",
  newline: "end of line",
  indent: "an indented block",
  dedent: "end of block",
  kw_not: "'not'",
  kw_with: "'with'",
  kw_fork: "'fork'",
  semicolon: "';'",
  kw_spark: "'spark'",
};

export function humanizeToken(tok: string): string {
  const key = tok.trim();
  const mapped = SURFACE_TOKEN_MAP[key];
  if (mapped) return mapped;
  if (key.startsWith("kw_") && key.length > 3) {
    return `'${key.slice(3)}'`;
  }
  return key;
}

const CANONICAL_CODE_MAP: Record<string, string> = {
  GPU_FRONTEND_SYNTAX_ERROR: "SYNTAX_ERROR",
  GPU_FRONTEND_MALFORMED_DELIMITER: "UNMATCHED_DELIMITER",
  GPU_FRONTEND_LEXICAL_ERROR: "LEXICAL_ERROR",
  GPU_FRONTEND_UNTERMINATED_STRING: "LEXICAL_ERROR",
  GPU_FRONTEND_UNTERMINATED_COMMENT: "LEXICAL_ERROR",
  LEX_UNEXPECTED_CHARACTER: "LEXICAL_ERROR",
  unknown_name: "UNKNOWN_VALUE",
  unknown_value: "UNKNOWN_VALUE",
  Io: "IO_ERROR",
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
    rawCodes: [
      "GPU_FRONTEND_SYNTAX_ERROR",
      "syntax",
      "syntax_error",
      "expected_token",
      "expected_expression",
      "expected_type",
      "expected_pattern",
      "unexpected_token",
      "invalid_literal",
      "private_marker",
    ],
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
  LEXICAL_ERROR: {
    code: "LEXICAL_ERROR",
    rawCodes: [
      "GPU_FRONTEND_LEXICAL_ERROR",
      "lexical_error",
      "LEX_UNEXPECTED_CHARACTER",
      "unterminated_string",
      "unterminated_comment",
      "GPU_FRONTEND_UNTERMINATED_STRING",
      "GPU_FRONTEND_UNTERMINATED_COMMENT",
      "integer_range",
      "float_range",
      "float_literal",
      "invalid_utf8",
      "string_literal",
      "string_escape",
      "reserved_layout",
      "reserved_selector_marker",
      "reserved_import_marker",
      "reserved_clause_marker",
      "layout_tab",
      "layout_indent",
      "layout_suite",
      "layout_dedent",
    ],
    title: "Invalid character, literal, string escape, or indentation layout",
    summary:
      "The lexer rejected a character, numeric range, string literal/escape, or indentation layout before parsing.",
    why:
      'Blot source must be valid UTF-8 indented with spaces (no tabs), top-level declarations start at column 1, strings close on one line using only `\\"`, `\\\\`, `\\n`, `\\r`, `\\t` escapes, and numeric literals must fit finite `U32` or `F32`.',
    before: `const big: U32 = 999999999999`,
    after: `const big: U32 = 4294967295`,
    checklist: [
      "Use spaces (never tabs) for indentation, start top-level declarations at column 1, and match dedents to enclosing blocks.",
      'Close string literals on the same line and use only `\\"`, `\\\\`, `\\n`, `\\r`, `\\t` escapes.',
      "Keep integer literals within `U32` (`0..4294967295`) and float literals within finite `F32`.",
    ],
  },
  UNSUPPORTED_EXPRESSION: {
    code: "UNSUPPORTED_EXPRESSION",
    rawCodes: ["unsupported_expression"],
    title: "Unsupported expression syntax (commonly bare `[...]` list literal)",
    summary: "This expression form is not supported in executable Blot code.",
    why:
      "Bare `[1, 2, 3]` list literals are retired. Blot has one unified owned array type `#[T]` constructed with `#[1, 2, 3]`.",
    before: `#entry func main (): #[U32] => return [1, 2, 3]`,
    after: `#entry func main (): #[U32] => return #[1, 2, 3]`,
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
      "Most commonly caused by omitting `$` on a sum-type constructor (`Some 1` instead of `$Some 1`), using `None` instead of `$Nothing`, using `String` instead of `Text`, a typo in a local/global name, or forgetting an `import`.",
    before: `type Opt is data = $Some U32 | $Nothing
#entry func main (): Opt => return Some 1`,
    after: `type Opt is data = $Some U32 | $Nothing
#entry func main (): Opt => return $Some 1`,
    checklist: [
      "Prefix every data constructor with `$` in expressions and patterns (`$Some x`, `$Nothing`, `$Vec2 { x: 1.0, y: 2.0 }`).",
      "Use `Text` (prelude alias for `#[U32]` with `std/text`) instead of `String`/`str`, and capitalized scalar types (`U32`, `F32`, `Bool`, `Unit`).",
      "Check for typos against declared `func` / `const` / `let` names and verify required `import` statements.",
    ],
  },
  MISSING_MEMBER: {
    code: "MISSING_MEMBER",
    rawCodes: ["missing_member"],
    title: "Receiver type has no associated member or field with this name",
    summary:
      "The `.member` projection or associated call does not exist on the receiver's inferred type.",
    why:
      "Blot arrays expose `.length` (not `.len`), records only expose declared fields, and module functions like `F32.sqrt x` are namespaced rather than implicit receiver methods unless declared as associated functions.",
    before: `#entry func main (): U32 =>
  let xs = #[1, 2, 3]
  return xs.len`,
    after: `#entry func main (): U32 =>
  let xs = #[1, 2, 3]
  return xs.length`,
    checklist: [
      "Check the exact record fields or associated functions available on the receiver type.",
      "Use `.length` (not `.len`) on `#[T]` / `Array T`.",
      "Use `.copy` for explicit deep copies and `@storage.push arr item` to append to an owned array.",
    ],
  },
  UNKNOWN_RECORD_FIELD: {
    code: "UNKNOWN_RECORD_FIELD",
    rawCodes: [
      "unknown_record_field",
      "missing_field",
      "unknown_field",
      "missing_record_field",
      "record_constructor",
    ],
    title:
      "Record literal, pattern, or field access references an unknown or missing field",
    summary:
      "A record expression, pattern, projection, or field update either omitted a required field or named a field not declared on the record type.",
    why:
      "Blot records are statically checked against their exact declared field set. Every field in a record literal must match the target type, and record updates (`r.field := ...`) require a physical field on `r`.",
    before: `type Pt = { x: U32, y: U32 }
#entry func main (): U32 =>
  let p: Pt = { x: 1, z: 2 }
  return p.x`,
    after: `type Pt = { x: U32, y: U32 }
#entry func main (): U32 =>
  let p: Pt = { x: 1, y: 2 }
  return p.x`,
    checklist: [
      "Match every field name in the record literal, pattern, or projection to the record type's declared fields.",
      "Supply all required fields when constructing a record (or update an existing binding's field with `p.x := ...`).",
      "For nominal data records (`type Pt is data = $Pt { x: U32, y: U32 }`), construct via `$Pt { x: 1, y: 2 }`.",
    ],
  },
  AMBIGUOUS_MEMBER: {
    code: "AMBIGUOUS_MEMBER",
    rawCodes: [
      "ambiguous_member",
      "ambiguous_operator",
      "ambiguous_associated",
      "ambiguous_qualified",
      "ambiguous_state",
      "missing_associated",
    ],
    title:
      "Member, operator, or associated dispatch is ambiguous or unresolved",
    summary:
      "The checker could not uniquely resolve a member access, operator, state type, or associated function from the available type information.",
    why:
      "Dispatching an overloaded operator, associated result function, or field/method collision requires concrete receiver or destination types and non-colliding member names.",
    before: `func empty_len (): U32 =>
  let xs = #[]
  return xs.length`,
    after: `func empty_len (): U32 =>
  let xs: #[U32] = #[]
  return xs.length`,
    checklist: [
      "Add an explicit type annotation on ambiguous empty arrays (`let xs: #[U32] = #[]`), state bindings, or return types.",
      "Check that both operands of an operator have compatible concrete types (no implicit `U32`/`F32` mixing).",
      "Avoid giving a record field and an associated function on the same type the exact same name.",
    ],
  },
  MISSING_IMPLEMENTATION: {
    code: "MISSING_IMPLEMENTATION",
    rawCodes: [
      "missing_implementation",
      "incompatible_implementation",
      "undetermined_implementation",
      "orphan_implementation",
      "overlapping_implementation",
      "recursive_evidence",
      "recursive_associated_type",
      "associated_limit",
      "missing_type_member",
      "associated_arity",
      "missing_predicate",
    ],
    title: "Contract implementation or associated type evidence failed",
    summary:
      "A required contract implementation is missing, overlapping, orphan, cyclic, or fails to satisfy its prerequisites or associated type members.",
    why:
      "Blot resolves contract constraints coherently at compile time without runtime reflection. Every required contract predicate must match a single coherent implementation whose prerequisites and associated types terminate.",
    before: `type Box = { v: U32 }
func eq_box (a: Box) -> (b: Box): Bool => return a == b`,
    after: `type Box = { v: U32 }
func eq_box (a: Box) -> (b: Box): Bool => return a.v == b.v`,
    checklist: [
      "Provide an explicit contract implementation (or compare fields directly) for the concrete type.",
      "Define implementations in the module declaring either the contract or the target nominal type (avoid orphans and overlaps).",
      "Break any cyclic prerequisite or associated-type equations and supply every required associated type member.",
    ],
  },
  UNKNOWN_CONSTRUCTOR: {
    code: "UNKNOWN_CONSTRUCTOR",
    rawCodes: [
      "unknown_constructor",
      "constructor_marker",
      "constructor_arity",
      "recursive_tag",
    ],
    title: "Invalid data constructor name, `$` marker, arity, or recursive tag",
    summary:
      "A `$Constructor` expression, pattern, or `is data` declaration used an unknown constructor name, wrong payload arity, or unboxed recursive layout.",
    why:
      "Every algebraic data constructor in Blot starts with `$`, must match a variant declared in a `type ... is data` definition, and must receive the exact number of payload arguments.",
    before: `type Opt is data = $Some U32 | $Nothing
#entry func main (): Opt => return $Some 1 2`,
    after: `type Opt is data = $Some U32 | $Nothing
#entry func main (): Opt => return $Some 1`,
    checklist: [
      "Verify the `$Constructor` spelling matches a declared `type ... is data` variant in scope.",
      "Pass the exact payload expected by the variant (e.g. `$Some 1`, `$Nothing`, `$Pair (1, 2)`).",
      "Use `#[Node]` indices/arrays instead of directly self-recursive value tags.",
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
    before: `#entry func main (): U32 => return 1.5`,
    after: `#entry func main (): F32 => return 1.5`,
    checklist: [
      "Convert explicitly between `U32` and `F32` with `@u32.to_f32` or `@f32.to_u32` (or `U32.to_f32` / `F32.to_u32`).",
      "Remember curried call syntax: `add a b` passes two curried args, whereas `f (a, b)` passes one 2-tuple.",
      "Write integer literals without decimals (`1`) and float literals with decimals (`1.0`).",
    ],
  },
  INFINITE_TYPE: {
    code: "INFINITE_TYPE",
    rawCodes: [
      "infinite_type",
      "type_arity",
      "type_parameter",
      "type_argument",
      "duplicate_type_parameter",
      "duplicate_type_field",
      "recursive_type_alias",
      "recursive_contract",
      "contract_arity",
      "annotation_kind_mismatch",
      "invalid_annotation",
      "unsupported_type",
      "unresolved_type",
      "skolem_escape",
      "rank_mismatch",
      "higher_rank_constraint",
      "invalid_constraint",
      "package_expected",
      "package_witness_mismatch",
      "package_escape",
    ],
    title: "Malformed, cyclic, unsupported, or escaping type annotation",
    summary:
      "A type expression failed well-formedness, arity, kind, occurs-check, rank, or concrete-representation checking.",
    why:
      "Blot requires finite, well-kinded types with concrete representations for code emission. Common causes include writing `String` instead of `Text`, passing the wrong number of type arguments (e.g. `Maybe` without `U32`), cyclic type aliases, or letting a local type variable escape.",
    before: `#entry func main (s: String): U32 => return s.length`,
    after: `#entry func main (s: Text): U32 => return s.length`,
    checklist: [
      "Use `Text` (not `String`/`str`) for Unicode scalar strings, and `U32`/`F32`/`Bool`/`Unit`/`#[T]` for built-ins.",
      "Supply the exact number of type arguments required by generic types (`Maybe U32`, `Result [U32, Text]`).",
      "Add concrete type annotations so every lowered value has a known representation, and avoid cyclic `type` aliases.",
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
    before: `func consume (xs: own #[U32]): U32 => return xs.length
#entry func main (): U32 =>
  let a = #[1, 2, 3]
  let n = consume a
  return n + a.length`,
    after: `func consume (xs: own #[U32]): U32 => return xs.length
#entry func main (): U32 =>
  let a = #[1, 2, 3]
  let n = consume a.copy
  return n + a.length`,
    checklist: [
      "Pass `name.copy` (or `(row.xs.copy)` for a field projection in a call) at the move site if you need to keep reading it afterward.",
      "Or return the owned value from the `own` function and thread it forward (`let a = update a`).",
      "If the callee only reads the array, remove `own` from its parameter so it borrows instead of moving.",
    ],
  },
  ALIASED_UPDATE: {
    code: "ALIASED_UPDATE",
    rawCodes: ["aliased_update", "borrow_conflict"],
    title: "In-place `:=` or storage mutation on aliased/borrowed value",
    summary:
      "This `:=` index write, `@storage.push`, or `@storage.truncate` mutates storage that another live name, borrow, `with` capture, or caller may still observe.",
    why:
      "Blot's `:=` operator updates array storage in place only when the compiler statically proves unique ownership. Updating through a borrowed parameter or while `let alias = arr` is still used later would expose mutation through an immutable alias.",
    before: `#entry func main (): U32 =>
  let a = #[1, 2, 3]
  let b = a
  a[0] := 99
  return a[0] + b[0]`,
    after: `#entry func main (): U32 =>
  let a = #[1, 2, 3]
  let b = a.copy
  a[0] := 99
  return a[0] + b[0]`,
    checklist: [
      "If a local `let b = a` is still read later, snapshot with `let b = a.copy` (or finish reading `b` before mutating `a`).",
      "If `a` is a function parameter, mark it `own` (`func f (a: own #[U32]): #[U32]`) so the caller transfers unique ownership.",
      "Inside `with` handlers or captures, avoid aliasing the mutated binding outside the handler; copy before entering or thread state explicitly.",
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
    before: `func consume_and_grow (xs: own #[U32]): #[U32] => return xs
func bad (xs: #[U32]): #[U32] => return consume_and_grow xs`,
    after: `func consume_and_grow (xs: own #[U32]): #[U32] => return xs
func good (xs: own #[U32]): #[U32] => return consume_and_grow xs`,
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
    after: `func pick (xs: own #[U32]): #[U32] => return xs`,
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
      "Declarations marked `#entry` cannot leave algebraic effects unhandled or use parameter/result types outside the raw ABI-8 boundary contract.",
    why:
      "Raw `#entry` accepts ABI-8 boundary types (`Unit`, `Bool`, `U32`, `F32`, `#[U32]`, `#[F32]`, or one `! {Foreign}` host callback), while `#kernel` and `#process` accept FlatNumeric / PersistentSafe structs and numeric arrays; fixed-size arrays `#[N; T]` and closures cannot cross raw `#entry`, and every effect must be handled lexically with `with ...:` or `do <provider>:`.",
    before: `type Clock is effect = { now: Unit -> U32 }
#entry func main (): U32 =>
  use t <- Clock.now ()
  return t`,
    after: `type Clock is effect = { now: Unit -> U32 }
#entry func main (): U32 =>
  with Clock = { now: func () => return 42 }:
    use t <- Clock.now ()
    return t`,
    checklist: [
      "Handle every effect reported in `(unhandled: Effect.op)` with `with Effect = { op: func ... => ... }:` or `do provider:`.",
      "Use ABI-8 boundary types on raw `#entry`: `Unit`, `Bool`, `U32`, `F32`, `#[U32]`, `#[F32]`, or one `! {Foreign}` host callback.",
      "For FlatNumeric / PersistentSafe structs and typed packets, use `#kernel` or `#process` (fixed-size `#[N; T]` and closures cannot cross raw `#entry`).",
    ],
  },
  EFFECT_MISMATCH: {
    code: "EFFECT_MISMATCH",
    rawCodes: [
      "effect_mismatch",
      "const_effect",
      "let_effect",
      "initializer_effect",
    ],
    title:
      "Effectful computation used where pure code or a different effect row is required",
    summary:
      "An expression performs an algebraic effect that is not permitted in this pure context (`const`, `let`, module initializer, or pure function signature).",
    why:
      "Blot functions, `const` definitions, and top-level initializers are pure by default. Effectful calls must be bound with `use x <- ...` inside an effectful scope or handled locally with `with` / `do`.",
    before: `type Clock is effect = { now: Unit -> U32 }
func read_time (): U32 =>
  let t = Clock.now ()
  return t`,
    after: `type Clock is effect = { now: Unit -> U32 }
func read_time (): U32 =>
  use t <- Clock.now ()
  return t`,
    checklist: [
      "Use `use x <- effect_call` (not `let x = ...`) to invoke effectful operations.",
      "Handle local effects with `with Effect = { ... }:` or `do provider:` before crossing a pure `const` or function boundary.",
      "Ensure both branches of an `if`/`case` and handler bodies match the expected effect row.",
    ],
  },
  SEALED_EFFECT: {
    code: "SEALED_EFFECT",
    rawCodes: [
      "sealed_effect",
      "unknown_effect",
      "effect_arity",
      "effect_family",
      "effect_member",
      "invalid_effect_annotation",
      "infinite_effect",
      "operation_signature",
      "operation_target",
      "invalid_provider",
      "invalid_state_provider",
      "resolver_required",
      "type_constructor_required",
      "effect_identity_scope",
      "capability_escape",
      "open_effect_descriptor",
      "unsupported_polymorphic_effect_label",
    ],
    title: "Invalid effect declaration, provider, handler, or capability scope",
    summary:
      "An algebraic effect reference, effect row annotation, handler operation signature, provider, or scoped capability failed effect checking.",
    why:
      "Effect declarations must be declared with `type Name is effect = { op: In -> Out }`, handler operations must match their declared signatures, and scoped capabilities or resolvers cannot escape their lexical handler.",
    before: `type Clock is effect = { now: Unit -> U32 }
#entry func main (): U32 =>
  with Clock = { missing: func () => return 0 }:
    return 0`,
    after: `type Clock is effect = { now: Unit -> U32 }
#entry func main (): U32 =>
  with Clock = { now: func () => return 42 }:
    use t <- Clock.now ()
    return t`,
    checklist: [
      "Check the effect family and operation names against the `type Name is effect = { ... }` declaration.",
      "Match every handler function's parameter and return types to the effect's operation signatures.",
      "Keep scoped effect capabilities and resolvers inside the `with` / `do` block that provides them.",
    ],
  },
  KERNEL_EFFECTFUL: {
    code: "KERNEL_EFFECTFUL",
    rawCodes: [
      "kernel_effectful",
      "spark_effectful",
      "spark_capture",
      "spark_generator",
    ],
    title:
      "`#kernel`, `#process`, or `spark` body performs an effect or invalid capture",
    summary:
      "A `#kernel`, `#process`, or `spark` SIMD comprehension must be completely pure (`! {}`) and cannot perform algebraic effects or invalid captures.",
    why:
      "Kernels, processes, and SIMD `spark` loops run across parallel lanes or isolated workers without ambient effect handlers. Host I/O and effectful orchestration belong in the caller or host boundary.",
    before: `type Clock is effect = { now: Unit -> U32 }
#kernel func step (x: U32): U32 =>
  use t <- Clock.now ()
  return x + t`,
    after: `#kernel func step (x: U32): U32 =>
  return x + 1`,
    checklist: [
      "Keep `#kernel` and `#process` functions pure (`! {}`); pass host-read values in as parameters instead of calling effects inside the kernel.",
      "Keep `spark #[expr | i <- 0 .. n]` pure with simple range generators and read-only outer inputs.",
      "Move effect handling (`with ...:` / `use ... <-`) to the caller or host boundary.",
    ],
  },
  KERNEL_TYPE: {
    code: "KERNEL_TYPE",
    rawCodes: ["kernel_type", "kernel_callable", "simd_lane_literal"],
    title: "Invalid `#kernel` / `#process` wire type or SIMD lane literal",
    summary:
      "A `#kernel` or `#process` signature uses a type that does not satisfy FlatNumeric / PersistentSafe layout rules, or a SIMD intrinsic received a non-literal lane index.",
    why:
      "Worker kernels and persistent processes exchange flat, fixed-stride packets without closures or unserialized handles, and Wasm SIMD shuffle/swizzle/broadcast instructions require compile-time literal lane indices.",
    before: `#kernel func bad (f: U32 -> U32): U32 => return f 1`,
    after: `#kernel func good (x: U32): U32 => return x + 1`,
    checklist: [
      "Use FlatNumeric scalars, flat records, or numeric arrays (`#[U32]`, `#[F32]`) for `#kernel` inputs/outputs and PersistentSafe types for `#process` state/messages.",
      "Pass in-range `U32` literals directly to SIMD shuffle, swizzle, and broadcast intrinsics.",
    ],
  },
  NO_ENTRY: {
    code: "NO_ENTRY",
    rawCodes: ["no_entry", "entry_let_type", "entry_module"],
    title: "Missing or misplaced `#entry`, `#kernel`, or `#process` export",
    summary:
      "Building a Wasm binary requires at least one `#entry`, `#kernel`, or `#process` declaration in the entry module with a supported export signature.",
    why:
      "Library modules can be checked with `blot check`, but `blot build` needs an exported entry point declared in the entry module itself (not only in imported modules).",
    before: `func helper (x: U32): U32 => return x + 1`,
    after: `func helper (x: U32): U32 => return x + 1
#entry func main (x: U32): U32 => return helper x`,
    checklist: [
      "Add an `#entry func main (...): ... => ...`, `#kernel`, or `#process` declaration to the entry module before running `blot build`.",
      "Use `blot check` to type-check library modules without `#entry`.",
      "Keep `#entry` declarations in the root entry module, not inside imported library modules.",
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
    before: `func unwrap (opt: Maybe U32): U32 =>
  let $Some value = opt
  return value`,
    after: `func unwrap (opt: Maybe U32): U32 =>
  let $Some value = opt else:
    return 0
  return value`,
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
      "Two top-level declarations, import aliases, record fields, or pattern bindings share the same identifier.",
    why:
      "Module declarations, record fields, and pattern variables must have distinct names. Local variables can be updated with `:=` rather than re-declaring conflicting bindings.",
    before: `const x = 1
const x = 2`,
    after: `const x = 1
const y = 2`,
    checklist: [
      "Rename one of the duplicate top-level `func` / `const` / `type` declarations or import aliases.",
      "Ensure every field in a record literal/type and every variable in a pattern appears once.",
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
#entry func main (): U32 =>
  count := 1
  return count`,
    after: `#entry func main (): U32 =>
  let count = 0
  count := 1
  return count`,
    checklist: [
      "Introduce local state with `let name = initial` before updating with `name := next`.",
      "For persistent cross-turn state, use `#process` instead of mutable module globals.",
    ],
  },
  PRIVATE_ACCESS: {
    code: "PRIVATE_ACCESS",
    rawCodes: [
      "private_access",
      "private_identity_escape",
      "abstract_representation_access",
      "descriptor_private",
      "std_only_intrinsic",
    ],
    title:
      "Attempted access to a private declaration, abstract representation, or std-only intrinsic",
    summary:
      "This expression references a module-private symbol, inspects an abstract type's hidden representation, or invokes an intrinsic reserved for `std/`.",
    why:
      "Blot enforces module encapsulation and abstract type boundaries across modules; internal primitives under `std/` are exposed through safe standard-library wrappers.",
    before:
      `// Accessing a private helper or std-only intrinsic from user code`,
    after:
      `// Export the helper publicly from its module, or call the std/ wrapper`,
    checklist: [
      "Remove `private` on declarations intended for import by other modules.",
      "Use the module's public constructor/accessor functions instead of reaching into an abstract type's representation.",
      "Replace `std`-only intrinsics with the corresponding `std/` library function.",
    ],
  },
  CONTROL_FLOW_ERROR: {
    code: "CONTROL_FLOW_ERROR",
    rawCodes: [
      "break_scope",
      "continue_scope",
      "unreachable_statement",
      "non_exiting_fallback",
      "return_outside_block",
      "return_across_continuation",
      "case_arm_return",
      "guard_fallthrough",
      "dead_rebinding",
      "call_arity",
      "intrinsic_arity",
      "unknown_intrinsic",
      "function_target",
      "literal_required",
      "pattern_arity",
      "pattern_bindings",
      "value_pattern_type",
      "alternative_bindings",
      "product_arity",
      "product_index",
      "product_index_literal",
      "unknown_product_shape",
    ],
    title: "Invalid control flow, call/pattern arity, or tuple/intrinsic usage",
    summary:
      "A `break`/`continue`/`return`/`else:` statement, function/intrinsic call, or tuple/pattern expression violated scoping or arity rules.",
    why:
      "`break` and `continue` require an enclosing loop or `do:` block, refutable `let ... else:` fallbacks must exit, and intrinsics, patterns, and tuples require exact arities and valid names.",
    before: `#entry func main (): U32 =>
  break 1`,
    after: `#entry func main (): U32 =>
  return do:
    break 1`,
    checklist: [
      "Use `break`/`continue` only inside loops or `do:` blocks, and `return` inside function bodies.",
      "Ensure every `let <pat> = <expr> else:` suite exits via `return`, `break`, or `continue`.",
      "Check intrinsic names (`@u32.add`, `@storage.push`, ...) and pass the exact argument/tuple/pattern arity.",
    ],
  },
  STORAGE_ERROR: {
    code: "STORAGE_ERROR",
    rawCodes: [
      "storage_unsupported",
      "storage_borrow_conflict",
      "storage_escape",
      "ownership_unproved",
      "collector_free_unproved",
      "own_parameter",
      "own_function_value",
      "lent_result_value",
      "kept_value",
      "duplicate_owner",
      "borrow_escape",
      "once_reused",
      "multiplicity_unknown",
      "cleanup_not_safe",
      "usage_evidence_mismatch",
      "usage_analysis_limit",
    ],
    title: "Scoped storage, ownership proof, or borrow lifetime violation",
    summary:
      "The compiler could not prove safe collector-free ownership, scoped storage lifetimes, or usage multiplicity for this value or call.",
    why:
      "Blot compiles without a garbage collector by statically proving every allocation has a clear owner, no borrowed storage escapes its owner, and `own` functions are called directly rather than passed as first-class values.",
    before: `func take (xs: own #[U32]): U32 => return xs.length
#entry func main (): U32 =>
  let f = take
  return f #[1, 2]`,
    after: `func take (xs: own #[U32]): U32 => return xs.length
#entry func main (): U32 =>
  return take #[1, 2]`,
    checklist: [
      "Call functions with `own` parameters directly rather than storing or passing them as first-class function values.",
      "Do not let borrowed storage escape its owning scope; return `.copy` or transfer ownership via `own`.",
      "Avoid reusing `once` resources or mixing incompatible usage annotations.",
    ],
  },
  COMPTIME_ERROR: {
    code: "COMPTIME_ERROR",
    rawCodes: [
      "const_panic",
      "const_runtime_dependency",
      "cycle",
      "initialization_cycle",
      "constant_fuel",
      "constant_recursion",
      "constant_expression",
      "integer_divide_by_zero",
      "array_bounds",
      "backend_const_only",
      "stage_unavailable",
      "code_shape_mismatch",
      "cross_stage_authority",
      "staging_budget",
      "generated_binding_escape",
    ],
    title: "Compile-time evaluation, constant dependency, or staging error",
    summary:
      "Evaluating a `const` initializer or compile-time staged expression trapped, hit a dependency cycle, exceeded its evaluation budget, or crossed a stage boundary.",
    why:
      "`const` initializers must depend only on other `const` values (never top-level `let`), must terminate within the compile-time step/recursion budget without panicking or indexing out of bounds, and staged code must respect stage boundaries.",
    before: `const bad: U32 = 1 / 0`,
    after: `const ok: U32 = 1 / 1`,
    checklist: [
      "Check for compile-time division by zero, out-of-bounds constant array indexing, or `@panic` in `const` initializers.",
      "Do not read a top-level `let` from a `const` initializer, and break circular `const`/`let` dependencies.",
      "Keep compile-time loops bounded and respect staging boundaries.",
    ],
  },
  IMPORT_ERROR: {
    code: "IMPORT_ERROR",
    rawCodes: [
      "import_path",
      "missing_file",
      "import_cycle",
      "duplicate_alias",
      "invalid_alias",
      "invalid_prelude",
      "unknown_export",
      "module_loader_required",
      "dependency_failed",
      "source_validation",
      "resolution_budget",
      "declaration_modifier",
      "unknown_modifier",
      "unsupported_attribute",
    ],
    title:
      "Module import path, export resolution, alias, or declaration modifier error",
    summary:
      "Loading or resolving an imported module, configured directory alias, prelude path, exported symbol, or top-level modifier failed.",
    why:
      "Imports must use relative paths (`./foo`, `../bar`) or configured `--alias` / `blot.json` prefixes without import cycles, and every imported name must be publicly exported by the target module.",
    before: `import { does_not_exist } from "./helper"`,
    after: `import { helper } from "./helper"`,
    checklist: [
      "Use relative paths (`./module`) or configured aliases (`std/...`, package aliases in `blot.json`).",
      "Verify the target `.blot` file exists, compiles cleanly, and publicly exports the imported name.",
      "Break circular `import` cycles between modules and verify top-level modifiers/attributes.",
    ],
  },
  ASSET_IMPORT: {
    code: "ASSET_IMPORT",
    rawCodes: ["asset_import"],
    title: "Stage-0 asset generator or typed asset import failed",
    summary:
      "Compiling, executing, or validating a Stage-0 generator or asset parser for a virtual generated module failed.",
    why:
      "Blot's Stage-0 pipeline compiles each `.blot` generator with zero host capabilities, executes it against its input asset, and feeds the generated Blot source into the project build. Errors can occur during `compile`, `execute` (runtime trap), `result` (`$Err`), or `generated_source` checking.",
    before:
      `// Generator returns $Err "bad input" or emits invalid Blot syntax`,
    after:
      `// Fix the input asset or Stage-0 generator and re-run \`blot check\``,
    checklist: [
      "Inspect the `from <input> via <generator> (stage0 <phase>)` provenance line to see whether the failure is in the generator, input asset, or generated source.",
      "Check the generator itself directly with `blot check <generator.blot>`.",
      "Verify the generator exports `generate` with a supported Stage-0 signature (`#[U32]` or `{ path, bytes/text }` -> `#[U32]` or `Result`).",
    ],
  },
  IO_ERROR: {
    code: "IO_ERROR",
    rawCodes: [
      "Io",
      "io_error",
      "source_limit",
      "file_limit",
      "backend_limit",
      "inference_budget",
      "nesting_limit",
      "table_limit",
      "complexity",
      "capability_analysis_limit",
      "proof_analysis_limit",
    ],
    title: "I/O failure or compiler resource/complexity budget exceeded",
    summary:
      "Reading a file failed or the module exceeded a compiler safety limit (file size, file count, nesting depth, inference steps, or backend arena limit).",
    why:
      "The compiler enforces deterministic bounded budgets on file sizes, nesting depth, type inference work, and bootstrap arena sizes.",
    before: `// Deeply nested expression or missing unreadable input path`,
    after:
      `// Verify file path/permissions and split complex expressions into smaller helpers`,
    checklist: [
      "Verify the file path exists and is readable.",
      "Break very large functions, deep nesting, or highly polymorphic expressions into smaller annotated helpers.",
      "Ensure compile-time array constants stay within the 16 MiB bootstrap arena limit.",
    ],
  },
  TYPED_HOLE: {
    code: "TYPED_HOLE",
    rawCodes: ["typed_hole"],
    title: "Typed hole `@hole` reports expected type and in-scope bindings",
    summary:
      "An explicit `@hole` placeholder stopped compilation to report the expected type and compatible bindings at that position.",
    why:
      "`@hole` is an interactive development tool for discovering the exact type expected by the compiler before filling in the real expression.",
    before: `func inc (x: U32): U32 => return @hole`,
    after: `func inc (x: U32): U32 => return x + 1`,
    checklist: [
      "Read the expected type and local candidates reported by the hole diagnostic or editor completion.",
      "Replace `@hole` with a concrete expression of the expected type.",
    ],
  },
  UNSUPPORTED: {
    code: "UNSUPPORTED",
    rawCodes: [
      "unsupported",
      "unchecked",
      "unresolved_binding",
      "invalid_call",
      "invalid_operator",
      "unknown_operator",
      "operator_associativity",
      "operator_header_order",
      "operator_precedence",
      "duplicate_operator",
      "unsupported_prefix",
      "semantic",
      "invalid_proof_operand",
      "proof_scope_escape",
      "proof_runtime_use",
      "proof_mismatch",
      "contradictory_proof",
      "invalid_numeric_proof",
      "unbound_alias_row",
      "task_escape",
      "task_handle_consumed",
      "task_capture_transfer",
      "task_capability_shared",
      "task_regions_overlap",
      "task_host_contract",
      "task_budget",
      "requests_scope",
      "yield_scope",
      "request_loop_scope",
      "request_loop_body",
      "request_loop_range",
      "request_binding",
      "request_completion",
      "request_clause_fallthrough",
      "request_completion_fallthrough",
      "duplicate_request_handler",
      "request_case_scope",
    ],
    title:
      "Unsupported form, operator declaration, proof, or retired language feature",
    summary:
      "This construct uses an unsupported backend form, invalid custom operator/proof declaration, or a retired task/request syntax.",
    why:
      "Blot vNext removes legacy language tasks and unsupported forms in favor of `#kernel`, `#process`, `spark`, and standard curried functions and operators.",
    before:
      `// Using a retired task/request construct or invalid operator header`,
    after:
      `// Rewrite using standard Blot vNext functions, effects, #kernel, or #process`,
    checklist: [
      "Replace retired task/request syntax with `#kernel` / `#process` or explicit algebraic effects.",
      "Check custom operator precedence, associativity, and header order (or use standard prefix/infix operators).",
      "Simplify unsupported forms into standard Blot vNext expressions (`blot guide --cheatsheet`).",
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
  return DIAGNOSTIC_CATALOG[canonical] ??
    RAW_TO_ENTRY.get(canonical.toLowerCase());
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
    /^(?:private\s+)?(#entry\s+(?:func|const|let)|#kernel(?:\s+(?:func|const))?|#process(?:\s+const)?|func|const|let|type|impl|contract|effect)\s+([A-Za-z_][A-Za-z0-9_.]*)/;
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

function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function isFieldProjection(text: string): boolean {
  return /^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$/.test(text);
}

function isCallArgumentPosition(index: LineIndex, startByte: number): boolean {
  const lineIdx = byteOffsetToLineCol(index, startByte).line - 1;
  const lineStart = index.lineStarts[lineIdx] ?? 0;
  const before = sliceUtf8(index, lineStart, startByte);
  if (!/[ \t]+$/.test(before)) return false;
  const trimmedBefore = before.trimEnd();
  if (!trimmedBefore) return false;
  if (!/[A-Za-z0-9_$\])}]$/.test(trimmedBefore)) return false;
  if (
    /\b(?:return|break|if|then|else|in|and|or|not|let|const|use|case|of|with)$/
      .test(trimmedBefore)
  ) {
    return false;
  }
  return true;
}

function isBalancedParenParam(text: string): boolean {
  if (!text.startsWith("(") || !text.endsWith(")")) return false;
  let depth = 0;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === "(") depth++;
    else if (ch === ")") {
      depth--;
      if (depth === 0 && i < text.length - 1) return false;
      if (depth < 0) return false;
    }
  }
  return depth === 0;
}

function formatOwnParameterSuggestion(
  rawSubject: string,
  name: string,
): string {
  const trimmed = rawSubject.trim();
  if (isBalancedParenParam(trimmed)) {
    const m = /^\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([\s\S]+)\)$/.exec(
      trimmed,
    );
    if (m) {
      const ty = m[2].trim();
      if (/^own\b/.test(ty)) return trimmed;
      return `(${m[1]}: own ${ty})`;
    }
  }
  return `(${name}: own #[T])`;
}

function isInsideWithBlock(index: LineIndex, byteOffset: number): boolean {
  const line1 = byteOffsetToLineCol(index, byteOffset).line;
  const currentLine = index.lines[line1 - 1] ?? "";
  const currentIndent = currentLine.length - currentLine.trimStart().length;
  for (let i = line1 - 2; i >= 0; i--) {
    const line = index.lines[i];
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("//")) continue;
    const indent = line.length - line.trimStart().length;
    if (indent < currentIndent && /^with\b/.test(trimmed)) return true;
    if (indent === 0) break;
  }
  return false;
}

function extractRecordFields(operand: string): string[] {
  const trimmed = operand.trim();
  if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) return [];
  const inner = trimmed.slice(1, -1);
  const parts: string[] = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i < inner.length; i++) {
    const ch = inner[i];
    if (ch === "{" || ch === "(" || ch === "[") depth++;
    else if (ch === "}" || ch === ")" || ch === "]") depth--;
    else if (ch === "," && depth === 0) {
      parts.push(inner.slice(start, i));
      start = i + 1;
    }
  }
  parts.push(inner.slice(start));
  return parts
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
  if (record.explanation) return record.explanation;
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
  if (Array.isArray(record.contexts) && record.contexts.length > 0) {
    return record.contexts.map((ctx) => ({
      kind: ctx.kind,
      message: ctx.message,
      filename: ctx.filename,
      span: ctx.span ??
        (typeof ctx.start === "number" && typeof ctx.end === "number"
          ? { start: ctx.start, end: ctx.end }
          : null),
    }));
  }
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
    const expected = syn.expectedToken
      ? humanizeToken(syn.expectedToken)
      : null;
    const actual = syn.actualToken ? humanizeToken(syn.actualToken) : null;
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
      /^(?:private\s+)?(?:#entry\s+|#kernel\s+)?func\b.*->\s*[A-Z][A-Za-z0-9_]*\s*(?:=>|:|$)/
        .test(trimmedLine) && !trimmedLine.includes("): ")
    ) {
      fix =
        "Write the return type after `:` before `=>` (`func f (x: U32): U32 => ...`); `->` separates curried parameters.";
    } else if (
      trimmedLine.includes("{") &&
      /^(?:private\s+)?(?:#entry\s+|#kernel\s+)?(?:func|if|for|while|else)\b/
        .test(trimmedLine)
    ) {
      fix =
        "Blot uses indented suites after `=>` or `:`, not `{ ... }` braces.";
    } else if (trimmedLine.includes("&&") || trimmedLine.includes("||")) {
      fix =
        "Blot uses `and`, `or`, and `not` (not `&&`, `||`, `!`) for boolean operators.";
    } else if (/^(?:mut|var)\s+/.test(trimmedLine)) {
      fix =
        "Blot declares locals with `let x = ...` and updates them with `x := ...` (no `mut`/`var` keyword).";
    } else if (expected && actual) {
      fix =
        `Expected ${expected}, found ${actual}. Check indentation, \`=>\`, and \`:\` suite headers.`;
    } else if (actual) {
      fix =
        `Unexpected ${actual}. Check Blot syntax (see \`blot guide --cheatsheet\`).`;
    } else {
      fix =
        "Check Blot declaration and suite syntax (`blot guide --cheatsheet`).";
    }
    const primaryLabel = expected
      ? `expected ${expected}`
      : actual
      ? `unexpected ${actual}`
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
    if (snippet === "None" || /Unknown value `None`/.test(record.message)) {
      return {
        headline: "Unknown value `None`.",
        primaryLabel: "use `$Nothing` instead",
        fix:
          "Blot's prelude option constructors are `$Nothing` and `$Some x` (not `None`/`Some`).",
      };
    }
    if (snippet === "String" || snippet === "str") {
      return {
        headline: `Unknown value \`${snippet}\`.`,
        primaryLabel: "use `Text` instead",
        fix:
          "Blot's Unicode scalar string type is `Text` (prelude alias for `#[U32]`) with `std/text` helpers.",
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
    const typoMatch = /did you mean `([^`]+)`\?/.exec(record.message);
    if (typoMatch) {
      return {
        headline: record.message,
        primaryLabel: `did you mean \`${typoMatch[1]}\`?`,
        fix: `Replace \`${snippet || "this name"}\` with \`${typoMatch[1]}\`.`,
      };
    }
    return {
      headline: record.message,
      primaryLabel: "not in scope",
      fix:
        "Check spelling, add a leading `$` for data constructors (`$Some`), or import the defining module.",
    };
  }

  if (
    canonical === "UNKNOWN_TYPE" || canonical === "UNSUPPORTED_TYPE"
  ) {
    if (snippet === "String" || snippet === "str") {
      return {
        headline: `Unknown or unsupported type \`${snippet}\`.`,
        primaryLabel: "use `Text` instead",
        fix:
          "Blot's Unicode scalar string type is `Text` (prelude alias for `#[U32]`) with `std/text` helpers.",
      };
    }
    if (
      ["Int", "i32", "u32", "f32", "float", "bool", "int"].includes(snippet)
    ) {
      return {
        headline: `Unsupported scalar type \`${snippet}\`.`,
        primaryLabel: "not a Blot type",
        fix:
          "Blot's built-in scalar types are `U32`, `F32`, `Bool`, and `Unit` (capitalized).",
      };
    }
  }

  if (
    canonical === "UNKNOWN_RECORD_FIELD" ||
    canonical === "MISSING_FIELD" ||
    canonical === "UNKNOWN_FIELD" ||
    canonical === "MISSING_RECORD_FIELD" ||
    canonical === "RECORD_CONSTRUCTOR"
  ) {
    const exp = getDispatchExplanation(record);
    const receiverType = exp?.candidates?.[0]?.operand ?? "";
    const fields = receiverType ? extractRecordFields(receiverType) : [];
    const member = exp?.member ??
      (snippet.includes(".")
        ? snippet.slice(snippet.lastIndexOf(".") + 1)
        : "");
    const fix = fields.length > 0
      ? `Available fields on \`${receiverType}\`: ${
        fields.map((f) => `\`${f}\``).join(", ")
      }.`
      : "Check the record type's declared field names and supply every required field in the record literal, pattern, or field update.";
    return {
      headline: record.message,
      primaryLabel: member
        ? `unknown record field \`.${member}\``
        : "invalid record field",
      fix,
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
    if (fields.length > 0) {
      fix = `Available fields on \`${receiverType}\`: ${
        fields.map((f) => `\`${f}\``).join(", ")
      }.`;
    } else if (member === "len") {
      fix = "Blot arrays use `.length` (not `.len`).";
    } else if (member === "push") {
      fix =
        "Use `@storage.push arr item` (or `arr.push item` if an array extension is in scope) to append to an owned `#[T]`.";
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
    const moveRaw = index && record.origin_kind === "moved" &&
        (record.origin_end ?? 0) > (record.origin_start ?? 0)
      ? sliceUtf8(index, record.origin_start!, record.origin_end!).trim()
      : "";
    const isProjMove = isFieldProjection(moveRaw) && !moveRaw.endsWith(".copy");
    const name = isProjMove
      ? moveRaw
      : subjectName || extractBindingIdent(snippet) || "this value";
    const copyExpr = isProjMove
      ? (index && isCallArgumentPosition(index, record.origin_start!)
        ? `(${moveRaw}.copy)`
        : `${moveRaw}.copy`)
      : subjectName
      ? `${subjectName}.copy`
      : "value.copy";
    const where = originLine ? ` at line ${originLine}` : "";
    return {
      headline:
        `\`${name}\` was already moved${where} and can no longer be used here.`,
      primaryLabel: `\`${name}\` used after move`,
      fix:
        `Pass \`${copyExpr}\`${where} to keep \`${name}\` live, or use the owned value returned by that call.`,
    };
  }

  if (canonical === "ALIASED_UPDATE" || canonical === "BORROW_CONFLICT") {
    const name = subjectName || extractBindingIdent(snippet) || "this value";
    const copyExpr = subjectName ? `${subjectName}.copy` : "value.copy";
    const where = originLine ? ` (line ${originLine})` : "";
    const inWithContext = /\bwith\b/i.test(record.message) ||
      (index !== null && !holderName && record.origin_kind !== "parameter" &&
        isInsideWithBlock(index, record.start));
    if (inWithContext) {
      return {
        headline:
          `Cannot mutate \`${name}\` in place while captured or aliased inside a \`with\` handler.`,
        primaryLabel: "aliased write inside `with` handler",
        fix:
          `Avoid aliasing \`${name}\` outside the \`with\` handler, snapshot with \`${copyExpr}\` before entering, or thread state explicitly through the handler.`,
      };
    }
    if (record.origin_kind === "borrowed") {
      if (holderName) {
        return {
          headline:
            `Cannot mutate \`${name}\` in place while \`${holderName}\` still borrows it.`,
          primaryLabel: "mutated while borrowed",
          fix:
            `Snapshot with \`let ${holderName} = ${copyExpr}\`${where}, or finish reading \`${holderName}\` before mutating \`${name}\`.`,
        };
      }
      return {
        headline:
          `Cannot mutate \`${name}\` in place while an active borrow or capture still observes it.`,
        primaryLabel: "mutated while borrowed",
        fix:
          `Copy with \`${copyExpr}\` before creating the borrow or capture${where}, or finish using the borrow before mutating \`${name}\`.`,
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
    if (record.origin_kind === "aliased") {
      return {
        headline:
          `Cannot mutate \`${name}\` in place because it was already aliased or escaped${where}.`,
        primaryLabel: "aliased or captured in-place write",
        fix:
          `Take an explicit copy (\`let local = ${copyExpr}\`) before mutating with \`:=\`, or avoid sharing/capturing \`${name}\`${where}.`,
      };
    }
    return {
      headline:
        `Cannot mutate \`${name}\` in place because another alias or capture may still observe it.`,
      primaryLabel: "aliased in-place write",
      fix:
        `Take an explicit copy (\`let local = ${copyExpr}\`) before updating with \`:=\`, or remove the earlier alias/capture.`,
    };
  }

  if (canonical === "OWN_ARGUMENT") {
    const name = subjectName || extractBindingIdent(snippet) || "this argument";
    const copyExpr = subjectName ? `${subjectName}.copy` : "value.copy";
    const ownParam = record.origin_kind === "parameter"
      ? formatOwnParameterSuggestion(subjectRaw, name)
      : "";
    const fix = record.origin_kind === "parameter"
      ? `Mark parameter \`${name}\` as \`own\` (e.g. \`${ownParam}\`) to forward ownership, or pass \`${copyExpr}\`.`
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
        "Raw `#entry` accepts ABI-8 boundary types (`Unit`, `Bool`, `U32`, `F32`, `#[U32]`, `#[F32]`, or one `! {Foreign}` host callback); use `#kernel` / `#process` for FlatNumeric / PersistentSafe structs and avoid fixed-size `#[N; T]` or closures on raw `#entry`.",
    };
  }

  if (
    canonical === "KERNEL_EFFECTFUL" ||
    canonical === "SPARK_EFFECTFUL" ||
    canonical === "SPARK_CAPTURE" ||
    canonical === "SPARK_GENERATOR"
  ) {
    if (canonical === "KERNEL_EFFECTFUL") {
      return {
        headline: record.message,
        primaryLabel: "effectful #kernel / #process",
        fix:
          "`#kernel` and `#process` functions must be pure (`! {}`); remove effects from the kernel body and move host I/O or effect handling to the caller/host boundary.",
      };
    }
    return {
      headline: record.message,
      primaryLabel: canonical === "SPARK_EFFECTFUL"
        ? "effectful spark body"
        : "invalid spark expression",
      fix:
        "Keep `spark #[...]` expressions pure (`! {}`) with simple range generators (`i <- 0 .. n`) and no mutable captures or effect calls.",
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
    canonical === "LET_EFFECT" || canonical === "INITIALIZER_EFFECT"
  ) {
    return {
      headline: record.message,
      primaryLabel: "effect not allowed here",
      fix:
        "Bind effectful calls with `use x <- ...` inside an effectful scope, or handle the effect locally with `with ...:` / `do <provider>:`.",
    };
  }

  const catalogEntry = lookupDiagnosticExplanation(canonical) ??
    lookupDiagnosticExplanation(record.code);
  return {
    headline: record.message,
    primaryLabel: canonical.toLowerCase().replace(/_/g, " "),
    fix: catalogEntry ? catalogEntry.checklist[0] ?? null : null,
  };
}

interface NormalizedBlame {
  originKind: string;
  originStart: number;
  originEnd: number;
  subjectStart: number;
  subjectEnd: number;
  holderStart: number;
  holderEnd: number;
}

function extractNormalizedBlame(record: RawDiagnosticRecord): NormalizedBlame {
  const detailsObj = record.details && !Array.isArray(record.details)
    ? record.details
    : undefined;
  const blameObj = record.blame;
  return {
    originKind: record.origin_kind || blameObj?.kind ||
      detailsObj?.origin_kind || "",
    originStart: record.origin_start ?? blameObj?.start ??
      detailsObj?.origin_start ?? 0,
    originEnd: record.origin_end ?? blameObj?.end ?? detailsObj?.origin_end ??
      0,
    subjectStart: record.subject_start ?? blameObj?.subjectStart ??
      detailsObj?.subject_start ?? 0,
    subjectEnd: record.subject_end ?? blameObj?.subjectEnd ??
      detailsObj?.subject_end ?? 0,
    holderStart: record.holder_start ?? blameObj?.holderStart ??
      detailsObj?.holder_start ?? 0,
    holderEnd: record.holder_end ?? blameObj?.holderEnd ??
      detailsObj?.holder_end ?? 0,
  };
}

function buildOwnParameterQuickFix(
  index: LineIndex,
  blame: NormalizedBlame,
  subjectName: string,
): DiagnosticQuickFix | null {
  if (
    blame.originKind !== "parameter" ||
    blame.originEnd <= blame.originStart ||
    !subjectName
  ) {
    return null;
  }
  const raw = sliceUtf8(index, blame.originStart, blame.originEnd);
  const trimmed = raw.trim();
  if (!isBalancedParenParam(trimmed)) return null;
  const m = /^(\s*\(\s*[A-Za-z_][A-Za-z0-9_]*\s*:\s*)([\s\S]+)\)\s*$/.exec(raw);
  if (!m) return null;
  const ty = m[2].trim();
  if (/^own\b/.test(ty)) return null;
  const insertAt = blame.originStart + textEncoder.encode(m[1]).length;
  return {
    title: `Mark parameter \`${subjectName}\` as \`own\``,
    startByte: insertAt,
    endByte: insertAt,
    newText: "own ",
    complete: true,
  };
}

function buildQuickFixes(
  canonical: string,
  record: RawDiagnosticRecord,
  index: LineIndex | null,
  blame: NormalizedBlame,
  subjectName: string,
): DiagnosticQuickFix[] {
  if (!index) return [];
  const [pStart, pEnd] = expandPointSpan(index, record.start, record.end);
  const snippet = sliceUtf8(index, pStart, pEnd);
  const trimmed = snippet.trim();
  const fixes: DiagnosticQuickFix[] = [];

  if (canonical === "SYNTAX_ERROR") {
    if (trimmed === "fn") {
      const line = index.lines[byteOffsetToLineCol(index, pStart).line - 1] ??
        "";
      const lineTrimmed = line.trim();
      const hasFatArrow = lineTrimmed.includes("=>");
      const hasBrace = lineTrimmed.includes("{");
      const hasRustReturnArrow = /->\s*(?:[A-Z][A-Za-z0-9_]*|#\[|\(\s*[A-Z])/
        .test(lineTrimmed);
      const hasCommaTypedParams =
        /\(\s*[A-Za-z_][A-Za-z0-9_]*\s*:[^)]*,\s*[A-Za-z_][A-Za-z0-9_]*\s*:/
          .test(lineTrimmed);
      if (
        hasFatArrow && !hasBrace && !hasRustReturnArrow && !hasCommaTypedParams
      ) {
        fixes.push({
          title: "Replace `fn` with `func`",
          startByte: pStart,
          endByte: pEnd,
          newText: "func",
          complete: true,
        });
      }
    }
  } else if (canonical === "UNSUPPORTED_EXPRESSION") {
    if (trimmed.startsWith("[") && !trimmed.startsWith("#[")) {
      fixes.push({
        title: "Convert bare list `[...]` to array `#[...]`",
        startByte: pStart,
        endByte: pStart,
        newText: "#",
        complete: true,
      });
    }
  } else if (canonical === "UNKNOWN_VALUE") {
    const ctorMatch = /did you mean `(\$[A-Za-z0-9_]+)`\?/.exec(record.message);
    if (ctorMatch) {
      fixes.push({
        title: `Replace with constructor \`${ctorMatch[1]}\``,
        startByte: pStart,
        endByte: pEnd,
        newText: ctorMatch[1],
        complete: true,
      });
    } else if (trimmed === "None") {
      fixes.push({
        title: "Replace `None` with `$Nothing`",
        startByte: pStart,
        endByte: pEnd,
        newText: "$Nothing",
        complete: true,
      });
    } else {
      const typoMatch = /did you mean `([^`]+)`\?/.exec(record.message);
      if (typoMatch) {
        fixes.push({
          title: `Replace with \`${typoMatch[1]}\``,
          startByte: pStart,
          endByte: pEnd,
          newText: typoMatch[1],
          complete: true,
        });
      }
    }
  } else if (canonical === "MISSING_MEMBER") {
    const exp = getDispatchExplanation(record);
    const receiverType = exp?.candidates?.[0]?.operand ?? "";
    const fields = receiverType ? extractRecordFields(receiverType) : [];
    if (
      fields.length === 0 && exp?.member === "len" && snippet.endsWith(".len")
    ) {
      const dotIdx = pEnd - 3;
      fixes.push({
        title: "Replace `.len` with `.length`",
        startByte: dotIdx,
        endByte: pEnd,
        newText: "length",
        complete: true,
      });
    }
  } else if (canonical === "SPENT_VALUE") {
    if (
      blame.originKind === "moved" &&
      blame.originEnd > blame.originStart &&
      subjectName
    ) {
      const moveRaw = sliceUtf8(index, blame.originStart, blame.originEnd);
      const moveTrimmed = moveRaw.trim();
      if (isFieldProjection(moveTrimmed) && !moveTrimmed.endsWith(".copy")) {
        if (isCallArgumentPosition(index, blame.originStart)) {
          const replacement = `(${moveTrimmed}.copy)`;
          fixes.push({
            title: `Pass \`${replacement}\` at move site`,
            startByte: blame.originStart,
            endByte: blame.originEnd,
            newText: replacement,
            complete: true,
          });
        } else {
          fixes.push({
            title: `Pass \`${moveTrimmed}.copy\` at move site`,
            startByte: blame.originEnd,
            endByte: blame.originEnd,
            newText: ".copy",
            complete: true,
          });
        }
      } else {
        const tokenRe = new RegExp(`\\b${escapeRegExp(subjectName)}\\b(?!\\.)`);
        const match = tokenRe.exec(moveRaw);
        if (match) {
          const prefixBytes = textEncoder.encode(
            moveRaw.slice(0, match.index + match[0].length),
          ).length;
          const insertAt = blame.originStart + prefixBytes;
          fixes.push({
            title: `Pass \`${subjectName}.copy\` at move site`,
            startByte: insertAt,
            endByte: insertAt,
            newText: ".copy",
            complete: true,
          });
        }
      }
    }
  } else if (canonical === "ALIASED_UPDATE") {
    if (
      blame.originKind === "borrowed" &&
      blame.originEnd > blame.originStart &&
      subjectName
    ) {
      const borrowText = sliceUtf8(index, blame.originStart, blame.originEnd);
      const eqIdx = borrowText.indexOf("=");
      if (eqIdx >= 0) {
        const rhs = borrowText.slice(eqIdx + 1);
        const tokenRe = new RegExp(`\\b${escapeRegExp(subjectName)}\\b(?!\\.)`);
        const match = tokenRe.exec(rhs);
        if (match) {
          const prefixBytes = textEncoder.encode(
            borrowText.slice(0, eqIdx + 1 + match.index + match[0].length),
          ).length;
          const insertAt = blame.originStart + prefixBytes;
          fixes.push({
            title: `Snapshot with \`${subjectName}.copy\``,
            startByte: insertAt,
            endByte: insertAt,
            newText: ".copy",
            complete: true,
          });
        }
      }
    } else if (blame.originKind === "parameter") {
      const paramFix = buildOwnParameterQuickFix(index, blame, subjectName);
      if (paramFix) fixes.push(paramFix);
    }
  } else if (canonical === "OWN_ARGUMENT") {
    if (blame.originKind === "parameter") {
      const paramFix = buildOwnParameterQuickFix(index, blame, subjectName);
      if (paramFix) fixes.push(paramFix);
    }
  } else if (canonical === "RESULT_NOT_OWNED") {
    if (trimmed && !trimmed.endsWith(".copy")) {
      fixes.push({
        title: `Return \`${trimmed}.copy\``,
        startByte: pEnd,
        endByte: pEnd,
        newText: ".copy",
        complete: true,
      });
    }
  }

  return fixes;
}

export function analyzeDiagnostic(
  record: RawDiagnosticRecord,
  source?: string,
): AnalyzedDiagnostic {
  const canonical = canonicalDiagnosticCode(record.code);
  const effectiveSource = source ?? record.virtual_source;
  const index = typeof effectiveSource === "string"
    ? buildLineIndex(effectiveSource)
    : null;
  const blame = extractNormalizedBlame(record);

  const subjectRaw = index && blame.subjectEnd > blame.subjectStart
    ? sliceUtf8(index, blame.subjectStart, blame.subjectEnd)
    : "";
  const subjectName = subjectRaw ? extractBindingIdent(subjectRaw) : "";
  const holderName = index && blame.holderEnd > blame.holderStart
    ? extractBindingIdent(sliceUtf8(index, blame.holderStart, blame.holderEnd))
    : "";

  const hasOrigin = Boolean(
    index && blame.originKind && blame.originEnd > blame.originStart,
  );
  const originLine = hasOrigin && index
    ? byteOffsetToLineCol(index, blame.originStart).line
    : null;

  const normalizedRecord: RawDiagnosticRecord = {
    ...record,
    origin_kind: blame.originKind,
    origin_start: blame.originStart,
    origin_end: blame.originEnd,
    subject_start: blame.subjectStart,
    subject_end: blame.subjectEnd,
    holder_start: blame.holderStart,
    holder_end: blame.holderEnd,
  };

  const { headline, primaryLabel, fix } = buildHeadlineAndFix(
    canonical,
    normalizedRecord,
    index,
    subjectName,
    subjectRaw,
    holderName,
    originLine,
  );

  const [pStart, pEnd] = index
    ? expandPointSpan(index, record.start, record.end)
    : [record.start, record.end];

  let secondarySpan:
    | { startByte: number; endByte: number; label: string }
    | null = null;
  if (hasOrigin) {
    let originLabel = "related here";
    if (blame.originKind === "moved") {
      const moveTrimmed = index
        ? sliceUtf8(index, blame.originStart, blame.originEnd).trim()
        : "";
      const movedLabelName =
        isFieldProjection(moveTrimmed) && !moveTrimmed.endsWith(".copy")
          ? moveTrimmed
          : subjectName;
      originLabel = movedLabelName
        ? `\`${movedLabelName}\` moved here`
        : "moved here";
    } else if (blame.originKind === "borrowed") {
      originLabel = holderName
        ? `borrowed by \`${holderName}\` here`
        : "borrowed here";
    } else if (blame.originKind === "aliased") {
      originLabel = "aliased here";
    } else if (blame.originKind === "parameter") {
      originLabel = "borrowed parameter (not `own`)";
    }
    secondarySpan = {
      startByte: blame.originStart,
      endByte: blame.originEnd,
      label: originLabel,
    };
  } else {
    const syn = getSyntaxDetail(record);
    if (
      syn.detailSpan &&
      (syn.detailSpan.start !== record.start ||
        syn.detailSpan.end !== record.end)
    ) {
      secondarySpan = {
        startByte: syn.detailSpan.start,
        endByte: syn.detailSpan.end,
        label: syn.actualToken
          ? `unexpected ${humanizeToken(syn.actualToken)} here`
          : "failed here",
      };
    }
  }

  const docEntry = lookupDiagnosticExplanation(canonical) ??
    lookupDiagnosticExplanation(record.code);
  const docRef = docEntry
    ? `blot explain ${docEntry.code} (skills/blot-diagnostics/SKILL.md#${docEntry.code})`
    : "blot explain --list (CHEATSHEET.md)";

  const quickFixes = buildQuickFixes(
    canonical,
    normalizedRecord,
    index,
    blame,
    subjectName,
  );

  return {
    canonicalCode: canonical,
    headline,
    primarySpan: { startByte: pStart, endByte: pEnd, label: primaryLabel },
    secondarySpan,
    fix,
    docRef,
    quickFixes,
  };
}

function toEnrichedSpan(
  startByte: number,
  endByte: number,
  label: string,
  filename: string | undefined,
  index: LineIndex | null,
): EnrichedDiagnosticSpan {
  const span: EnrichedDiagnosticSpan = {
    ...(filename !== undefined ? { filename } : {}),
    startByte,
    endByte,
    label,
  };
  if (index) {
    const startPos = byteOffsetToLineCol(index, startByte);
    const endPos = byteOffsetToLineCol(index, Math.max(startByte, endByte));
    span.line = startPos.line;
    span.col = startPos.col;
    span.endLine = endPos.line;
    span.endCol = endPos.col;
  }
  return span;
}

export function enrichDiagnostic(
  record: RawDiagnosticRecord,
  options: EnrichDiagnosticOptions = {},
): EnrichedDiagnostic {
  const effectiveSource = options.source ?? record.virtual_source;
  const index = typeof effectiveSource === "string"
    ? buildLineIndex(effectiveSource)
    : null;
  const analyzed = analyzeDiagnostic(record, effectiveSource);
  const scope = index
    ? findEnclosingScope(index, byteOffsetToLineCol(index, record.start).line)
    : null;

  const primarySpan = toEnrichedSpan(
    analyzed.primarySpan.startByte,
    analyzed.primarySpan.endByte,
    analyzed.primarySpan.label,
    record.filename,
    index,
  );

  const related: EnrichedDiagnosticSpan[] = [];
  const seenRelated = new Set<string>();
  const pushRelated = (span: EnrichedDiagnosticSpan) => {
    const key = `${
      span.filename ?? ""
    }:${span.startByte}:${span.endByte}:${span.label}`;
    if (seenRelated.has(key)) return;
    seenRelated.add(key);
    related.push(span);
  };

  if (analyzed.secondarySpan) {
    pushRelated(
      toEnrichedSpan(
        analyzed.secondarySpan.startByte,
        analyzed.secondarySpan.endByte,
        analyzed.secondarySpan.label,
        record.filename,
        index,
      ),
    );
  }

  for (const ctx of getDiagnosticContexts(record)) {
    if (ctx.span && ctx.span.end > ctx.span.start) {
      const ctxFile = ctx.filename ?? record.filename;
      const ctxSource = ctxFile && ctxFile !== record.filename
        ? options.relatedSources?.[ctxFile]
        : effectiveSource;
      const ctxIndex = typeof ctxSource === "string"
        ? (ctxFile === record.filename ? index : buildLineIndex(ctxSource))
        : null;
      pushRelated(
        toEnrichedSpan(
          ctx.span.start,
          ctx.span.end,
          ctx.message ?? ctx.kind ?? "related context",
          ctxFile,
          ctxIndex,
        ),
      );
    }
  }

  const { related: rawRelated, ...restRecord } = record;
  if (rawRelated && rawRelated.filename) {
    const relSource = rawRelated.filename === record.filename
      ? effectiveSource
      : options.relatedSources?.[rawRelated.filename];
    const relIndex = typeof relSource === "string"
      ? (rawRelated.filename === record.filename
        ? index
        : buildLineIndex(relSource))
      : null;
    pushRelated(
      toEnrichedSpan(
        rawRelated.start,
        rawRelated.end,
        "related location",
        rawRelated.filename,
        relIndex,
      ),
    );
  }

  return {
    ...restRecord,
    kind: "diagnostic",
    schemaVersion: DIAGNOSTIC_SCHEMA_VERSION,
    severity: "error",
    canonicalCode: analyzed.canonicalCode,
    rawCode: record.code,
    headline: analyzed.headline,
    scope,
    primarySpan,
    related,
    fix: analyzed.fix,
    quickFixes: analyzed.quickFixes,
    docRef: analyzed.docRef,
    ...(record.provenance ? { provenance: record.provenance } : {}),
  };
}

const defaultReadSource = async (path: string): Promise<string | undefined> => {
  try {
    return await Deno.readTextFile(path);
  } catch {
    return undefined;
  }
};

export async function enrichDiagnostics(
  records: RawDiagnosticRecord[],
  readSource: (path: string) => Promise<string | undefined> = defaultReadSource,
): Promise<EnrichedDiagnostic[]> {
  const cache = new Map<string, string | undefined>();
  const loadFile = async (path: string): Promise<string | undefined> => {
    if (!cache.has(path)) {
      cache.set(path, await readSource(path));
    }
    return cache.get(path);
  };
  const enriched: EnrichedDiagnostic[] = [];
  for (const record of records) {
    let source: string | undefined;
    if (record.filename) {
      source = await loadFile(record.filename);
    }
    if (source === undefined && record.virtual_source !== undefined) {
      source = record.virtual_source;
    }
    const relatedSources: Record<string, string | undefined> = Object.create(
      null,
    );
    if (
      record.related?.filename && record.related.filename !== record.filename
    ) {
      relatedSources[record.related.filename] = await loadFile(
        record.related.filename,
      );
    }
    for (const ctx of getDiagnosticContexts(record)) {
      if (ctx.filename && ctx.filename !== record.filename) {
        relatedSources[ctx.filename] = await loadFile(ctx.filename);
      }
    }
    enriched.push(enrichDiagnostic(record, { source, relatedSources }));
  }
  return enriched;
}

function formatProvenanceLine(provenance: Stage0Provenance): string {
  return provenance.generator
    ? `from ${provenance.input} via ${provenance.generator} (stage0 ${provenance.phase})`
    : `from ${provenance.input} (stage0 ${provenance.phase})`;
}

export function formatDiagnostic(
  record: RawDiagnosticRecord,
  options: FormatDiagnosticOptions = {},
): string {
  const file = options.displayFilename ?? record.filename ?? "<input>";
  const effectiveSource = options.source ?? record.virtual_source;
  const index = typeof effectiveSource === "string"
    ? buildLineIndex(effectiveSource)
    : null;
  const analyzed = analyzeDiagnostic(record, effectiveSource);
  const out: string[] = [`[${analyzed.canonicalCode}] ${analyzed.headline}`];

  if (record.provenance) {
    out.push(formatProvenanceLine(record.provenance));
  }

  if (index) {
    const pos = byteOffsetToLineCol(index, record.start);
    const scope = findEnclosingScope(index, pos.line);
    const base = basename(file);
    out.push(scope ? `in ${base} › ${scope}` : `in ${base}`);
    out.push(`at ${file}:${pos.line}:${pos.col}`);

    const spans: AnnotatedSpan[] = [];
    if (analyzed.secondarySpan) {
      spans.push({
        startByte: analyzed.secondarySpan.startByte,
        endByte: analyzed.secondarySpan.endByte,
        marker: "-",
        label: analyzed.secondarySpan.label,
      });
    } else {
      for (const ctx of getDiagnosticContexts(record)) {
        if (
          ctx.span && ctx.span.end > ctx.span.start &&
          (!ctx.filename || ctx.filename === record.filename)
        ) {
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
      label: analyzed.primarySpan.label,
    });

    out.push(...formatExcerpt(index, spans));
  } else {
    out.push(`at ${file}:${record.start}-${record.end}`);
  }

  if (
    record.related && record.related.filename &&
    record.related.filename !== record.filename
  ) {
    const relSource = options.relatedSources?.[record.related.filename];
    if (typeof relSource === "string") {
      const relPos = byteOffsetToLineCol(
        buildLineIndex(relSource),
        record.related.start,
      );
      out.push(
        `note: related at ${record.related.filename}:${relPos.line}:${relPos.col}`,
      );
    } else {
      out.push(
        `note: related at ${record.related.filename}:${record.related.start}-${record.related.end}`,
      );
    }
  }

  if (analyzed.fix) {
    out.push(`fix: ${analyzed.fix}`);
  }
  out.push(`doc: ${analyzed.docRef}`);

  return out.join("\n");
}

export async function formatDiagnosticReport(
  records: RawDiagnosticRecord[],
  readSource: (path: string) => Promise<string | undefined> = defaultReadSource,
): Promise<string> {
  const cache = new Map<string, string | undefined>();
  const loadFile = async (path: string): Promise<string | undefined> => {
    if (!cache.has(path)) {
      cache.set(path, await readSource(path));
    }
    return cache.get(path);
  };
  const rendered: string[] = [];
  for (const record of records) {
    let source: string | undefined;
    if (record.filename) {
      source = await loadFile(record.filename);
    }
    if (source === undefined && record.virtual_source !== undefined) {
      source = record.virtual_source;
    }
    const relatedSources: Record<string, string | undefined> = Object.create(
      null,
    );
    if (
      record.related?.filename && record.related.filename !== record.filename
    ) {
      relatedSources[record.related.filename] = await loadFile(
        record.related.filename,
      );
    }
    rendered.push(formatDiagnostic(record, { source, relatedSources }));
  }
  return rendered.join("\n\n");
}

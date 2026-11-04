# Parse source correspondence

All seven production sources in `compiler/src/parse/` have implementations with
matching filenames under this directory. The Zig sources remain unchanged.
No compiler, build, test, formatter, checker, or verification command was run.

- `token`: exact u32 token ordinals, immutable byte spans, complete keyword table.
- `symbols`: numeric identities, exact Wyhash, half-full power-of-two buckets,
  collision equality, read-only worker views and missing-name error boundary.
- `ast`: exact u32 node/usage/binder/numeric/code ordinals, typed side tables,
  declaration ownership, source origins and every metadata decoding helper.
- `lexer`: UTF-8 validation, private markers, maximal lexical scanning, comments,
  numeric decoding, indentation frames, operations layout and contextual tokens.
- `parser`: all declaration, type, expression, pattern, statement, package,
  staging, task and collection routines; flat operator reduction and recovery.
- `syntax_diagnostics`: actual delimiter pairing, publication causes and UTF-16.
- `source_operators`: reverse header/declaration validation, lexical/pattern
  scopes, complete expression traversal, primitives, requests, loop deferral,
  record schemas, control scopes, annotations and error propagation.

## Calling and ownership

Names use snake_case. Token constants retain Zig tag spelling (`eof`, etc).
AST constants use `tag_`, `code_`, `bindersort_`, `usagekind_`, `numericcode_`
prefixes; all backing values retain source order. `source_operators` constants
use `c_` and AST-local aliases use `a_`. No polymorphic untyped table is used.

Array owners belong to the caller. The following contexts contain fixed typed
`T[>..<]&` references. Initialization expects initially empty owners.

- `blot_parse_symbols::init(bytes,entries,buckets) -> Pool`.
- `blot_parse_lexer::init(tokens,comments,diagnostics) -> Result`.
- `blot_parse_ast::init(nodes,spans,extra,roots,runtime_names,constant_names,
  declaration_traits,declaration_nodes,diagnostics,operator_origins,
  type_conversion_origins) -> Tree`. Adds the absent node/span at index zero.

`lex(source,result) -> Error`; `parse(source,tokens,pool,tree) -> Error`;
`parse_with_fixities(source,tokens,pool,tree,inherited) -> Error`.
`validate<C>(tree,pool,context) -> Issue,bool,Error`.

Parser internal fallibility is held in `Parser.failure`; the first failure
stops token advancement and table mutation, and top-level recovery clears only
syntax errors. Other errors propagate through the public boundary. Growable
Goose array allocation uses the Goose runtime's allocation boundary; Goose does
not currently offer recoverable allocation failures for `push`/`resize`.

Float tokens are converted directly to binary32 using exact decimal integer
comparison against dyadic midpoints. This preserves nearest-even finite F32,
subnormal, overflow and halfway semantics without an F64 intermediate.

`parse_error.goose` lists parse-specific error names for shared error integration.

## Source-operator context adapter

`Validator<C>` calls every hook explicitly; required source authority is never
replaced by permissive defaults. The checker adapter implements the following
snake_case methods. `Scope` is a fixed record chosen by the adapter; the scope
returned by each start method is passed unchanged to its matching end method.
Optional values use `value,bool`, with false meaning absent.

| Method | Result |
| --- | --- |
| `source_duplicate_name()` | `Id,bool` |
| `source_operator_target_exists(Symbol)` | `bool,Error` |
| `source_value_exists(Symbol)` | `bool,Error` |
| `source_record_target(Symbol)` | `u32,Error` (record=0, other=1, missing=2) |
| `source_argument_is_type(Id,Id)` | `bool,Error` |
| `source_declaration_header(Id)` | `Error` |
| `source_request_header(Id)` | `Error` |
| `source_binding_annotation(Id)` | `Error` |
| `source_binding_finish(Id)` | `Error` |
| `source_expression_annotations(Id)` | `Error` |
| `source_binding_start(Id)` | `Scope,Error` |
| `source_binding_end(Scope)` | void |
| `source_implementation_start(Id)` | `Scope,Error` |
| `source_implementation_end(Scope)` | void |
| `source_annotations_stopped()` | `bool` |
| `source_control_validation()` | `bool` |
| `source_literal_point(Id)` | `u32` |
| `source_editor_probe(Id)` | `bool` |
| `source_private_constructor(Symbol)` | `bool` |
| `source_type_application(Symbol)` | `bool` |
| `source_record_field_exists(Symbol,Symbol)` | `bool,bool` |
| `source_missing_record_field(Symbol,const Id[:])` | `Symbol,bool` |
| `source_symbolic_declared(Symbol)` | `bool` |
| `source_intrinsic_known(Symbol)` | `bool` |
| `source_intrinsic_arity(Symbol)` | `i64,bool` |
| `source_non_callable_effect(Symbol)` | `bool` |
| `source_qualified_exists(Symbol,Symbol)` | `bool` |
| `source_constructor_exists(Symbol)` | `bool` |

Formerly optional hooks must have deliberate adapter defaults when the context
has no such capability: no-op annotations/header/start/end, false stop/control/
probe/private flags, and the node span's start for literal position. These
choices belong to the context adapter, not this validator.

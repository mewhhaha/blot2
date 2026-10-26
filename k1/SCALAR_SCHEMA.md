# Experimental typed scalar schema v2

This is the shared implementation seam for the private Goose scalar fixture.
It is not a complete K1 CheckedInterface, CheckedFunction, LoweringPlan, public
compiler or host bridge. The authority remains issue #37 and LANG, MEM, CORE
and EXEC. Preserve the existing CLI's fail-closed public check/build behavior.

## Source subset and result types

In the existing explicit-return short/body/value-block forms, one return operand
is either a single U32 atom or exactly one binary operation:

```text
atom := parameter | decimal_u32
expression := atom | atom "&" atom | atom "<" atom
```

An atom is a reference to the sole U32 parameter or an unsuffixed decimal in
0..4294967295. A single atom and `&` produce U32 and require source annotation
`U32 -> U32`; `<` produces Bool and requires `U32 -> Bool`. Both operands are
U32 and are evaluated left to right, exactly once. One bitwise operation or one
comparison is permitted: reject nesting, chaining, `&&`, equality, other
operators, parentheses and calls until independently specified. Bool inputs,
Bool literals and conditionals remain unsupported. An incompatible result
annotation is `k1_type_mismatch`; an unknown identifier is `k1_unbound_name`;
ordinary unproved arithmetic must not be silently accepted as a total operation.
The existing suite and lexical-target rules remain in force.

## Shared numeric IDs

Tags below belong to this prototype schema; tag zero is reserved for an absent
field. Value IDs are zero-based, with value 0 denoting the sole parameter; an
unused input field is also zero and is interpreted by the producer tag.
They are not asserted to be IDs assigned by the normative specification.

| Category | ID | Meaning |
| --- | ---: | --- |
| type | 1 | U32 |
| type | 2 | Bool |
| value producer | 1 | sole U32 parameter |
| value producer | 2 | U32 constant |
| value producer | 3 | binary operation |
| binary operation | 1 | `k1.u32.bitand.v1`, `&` |
| binary operation | 2 | `k1.u32.lt.v1`, unsigned `<` |
| return terminator | 1 | explicit `return` of `result_id` |

Registry operation 1 is `(U32,U32)->U32`, total bitwise conjunction, no
preconditions, effects, failure, identity generation, allocation or ownership
transition; it lowers to Wasm `i32.and` (0x71). Registry operation 2 is
`(U32,U32)->Bool`, total unsigned less-than with the same empty obligations; it
lowers to `i32.lt_u` (0x49), whose result is canonical 0 or 1. For both, all
operands are already evaluated values, and no separate proof fact is created by
this expression-only subset. Changing an operation's semantics, required policy
or ABI requires the version/key change mandated by the specifications.

## Frontend output

Keep `frontend::parse_scalar(source: u8[:]) -> ParseResult`. Existing fields and
meanings remain: `status: i64`, `kind: i64`, `literal: u32`, `start: i64`,
`end: i64`, `name_start: i64`, `name_end: i64`. On success, `kind` and
`literal` describe the left atom (`kind=0` parameter, `kind=1` literal), and
`start..end` is that atom's byte span. Add these fields, all `i64` unless noted:

```text
result_type                  # type ID 1 or 2
binary_op                    # 0 no operator; 1 bitand; 2 unsigned less-than
parameter_start, parameter_end
operator_start, operator_end
right_start, right_end
right_kind                   # 0 parameter, 1 literal; meaningful only if binary_op != 0
right_literal: u32           # meaningful only for a literal right atom
```

All spans are half-open UTF-8 byte offsets into the supplied immutable source.
For a unary expression, `operator_start`, `operator_end`, `right_start`,
`right_end`, `right_kind` and `right_literal` are zero. For a parameter atom,
its corresponding literal field is zero. Span validity and exact source
correspondence are independently checked before use. Do not retain a borrowed
source reference in ParseResult or Core. Existing status codes 0..6 retain
their meanings; status 7 is `k1_type_mismatch`. Fields other than status and
diagnostic `start..end` are not authoritative after a nonzero status.

## Owned transient Core

Place the dependency-free data definitions in `scalar_core.goose`, namespace
`scalar_core`:

```text
struct ScalarValue {
  producer: i64 = 0, type_id: i64 = 0, op_id: i64 = 0,
  literal: u32 = 0, left_id: i64 = 0, right_id: i64 = 0
}
struct ScalarCore {
  result_type: i64 = 0, value_count: i64 = 0,
  values: ScalarValue[4],
  terminator: i64 = 0, result_id: i64 = 0,
  name_start: i64 = 0, name_end: i64 = 0,
  parameter_start: i64 = 0, parameter_end: i64 = 0,
  left_start: i64 = 0, left_end: i64 = 0,
  operator_start: i64 = 0, operator_end: i64 = 0,
  right_start: i64 = 0, right_end: i64 = 0
}
```

`values` is fixed-size owned storage, not a pointer, slice or solver handle.
Use explicit zero-initialization when constructing it. Fields are a semantic
model; their in-memory layout is not a portable serialization.

Canonical construction rules, all mandatory:

1. `value_count` is 1..4 and `values[0]` is the sole parameter, producer 1,
   type 1. Its op, literal and inputs are zero.
2. Process atoms left to right. Each literal occurrence appends one producer-2,
   type-1 constant with its exact U32 bits and zero op/input fields. Every
   parameter use refers to value 0. Distinct literal occurrences get distinct
   records even when their bits match.
3. For binary source append exactly one producer-3 result, with op 1/type 1 or
   op 2/type 2, left/right IDs equal to the corresponding operand values and
   literal zero. Both IDs must refer to earlier values. For single-atom source
   there is no producer-3 value. `terminator=1`, `result_id` is the atom or
   binary result, and `result_type` equals its type.
4. Every value slot at or above `value_count` is all zeros. No dead or extra
   values, second parameter, implicit conversion, unknown tag, forward
   reference, or hidden operation is permitted. All absent operator/right spans
   are zero in the single-atom case. Name/parameter/operand/operator spans
   identify their exact corresponding source tokens. The completed private leaf
   has empty effects, no captures, no preconditions and synthesized resource
   bounds depth 1, frame 0; no other contract is implied by this record.

A separate builder may convert successful frontend output to this record; it is
not a validator. Do not lower unless independent validation succeeds. The
validator checks the entire source and each span before slicing, independently
re-recognizes source grammar/lexical targets and checks name resolution,
source/typed Core correspondence, type/operation schemas, canonical value
order, dominance, all zero/absent fields, and the result/return contract. It
rejects forged tags, extra records, bad type combinations and malformed spans.
No external source or serialized artifact can manufacture semantic authority by
claiming to have been previously validated.

## Emitter seam and ABI

The internal v2 emitter is `wasm::emit_scalar_v2(name: u8[:], plan:
scalar_plan::ScalarLoweringPlan) -> u8[]`; an empty array means rejection. The
driver independently validates source against transient Core, constructs and
validates the private plan, and passes the validated name and plan to emission.
The emitter independently rechecks the plan and its embedded Core. The plan is
a limited fixture model, not a complete K1 lowering plan or artifact. The
emitter additionally rejects malformed names, types, producer/operation
IDs, noncanonical record order and references. Values compile in semantic
order: parameter use as `local.get 1`, constant as `i32.const` signed LEB of
its U32 bits, then the registry-selected binary opcode. An unused parameter has
no effect. Single-atom programs retain their existing behavior.

The existing private callable convention remains `(environment:i32,
argument:i32) -> i32`, with environment zero. U32 results use their raw bits;
Bool results are exactly 0 or 1. This does not establish the complete ABI hash,
manifest, export wrapper, certificates or host protocol. Emitted Wasm must be
recomputed from validated Core, never accepted as authenticated merely because
a source/core header or digest matches.

## Artifact fence and test obligations

`BLK1SC01` remains the fenced existing unary scalar format. A typed binary
record requires a new schema identity (provisionally `BLK1SC02`); never decode
SC01 as SC02. Before publication, specify a deterministic, bounded byte layout
with explicit integer sizes, byte order, lengths, source identity and all
policy/ABI IDs; verify version/lengths/tags/indices before allocation, slicing
or table lookup. Unknown, incompatible and forged inputs fail closed. Existing
SC01 handling remains explicit until separately migrated. Schema v2 is not a
claim that a normative portable CheckedFunction is implemented.

Executable laws cover zero, one, `0x7fffffff`, `0x80000000`, and U32 maximum,
including constant-left and constant-right operations. Compare executed Wasm
against an unsigned native reference and verify Bool is 0/1. Negative laws
cover mismatched result annotations, unknown names, operand overflow, unsupported
syntax, forged types/IDs/inputs/spans/unused fields, out-of-order definitions,
and bad/incompatible artifact headers. Test short and block forms, validator
and artifact decoding independently, and rerun the affected integration suite.

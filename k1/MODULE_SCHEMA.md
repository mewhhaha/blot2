# Experimental multi-function U32 module schema v3

This is a narrow private-fixture contract, not general K1 admission or a
complete checked artifact. Preserve the public legacy default and the existing
K1 check/build fence. IDs and interfaces below coordinate this prototype; the
normative authority remains issue #37 and its four linked specifications.

## Source subset

Accept 1–256 distinct private, top-level `let name: U32 -> U32 = fn parameter`
declarations, using the existing explicit short-return, body-do-return or
return-value-do/break forms. Each function returns exactly one expression:

```text
atom := parameter | decimal_u32
expression := atom | atom "&" atom | callee "(" atom ")"
```

`&` is the existing total U32 bitwise conjunction. A call passes one U32 value,
with no implicit currying. All callees are top-level declarations in the same
module, collected before resolution; forward references are supported. A local
parameter shadows a top-level name, so calling that local U32 produces a type
mismatch. Every declaration, including unused declarations, must complete and
validate. Duplicate names, unbound names, and direct self/mutual recursion are
rejected. All Bool-valued functions, `<`, captures, indirect/nested calls,
multiple calls, call results combined with another operation, imports, effects,
multiple modules and other language constructs remain outside this v3 subset;
the existing v2 single-function fixture can still handle its Bool comparison.
The 256-function ceiling is a prototype subset restriction and reports
`k1_unsupported_feature`, not a new `K1-SEM-POLICY-1` source limit. The
normative 16 MiB source and syntax nesting limits still apply.

## Frontend ownership and status

`module_frontend::parse(source: u8[:]) -> Module, i64` returns an owned copy of
source and a declaration array on success, or an empty Module on failure. The
module may not retain any borrowed source pointers. `module_frontend::verify(
module: Module&) -> i64` independently checks the source against the owned
records and resolved graph, returning 0 for valid, 1 for invalid. It is not a
portable artifact validator. `Module` and `Declaration` live in namespace
`module_frontend` with these exact fields:

```text
struct Declaration {
  declaration_start: i64 = 0, declaration_end: i64 = 0,
  name_start: i64 = 0, name_end: i64 = 0,
  function_start: i64 = 0,
  parameter_start: i64 = 0, parameter_end: i64 = 0,
  return_start: i64 = 0,
  expression_start: i64 = 0, expression_end: i64 = 0,
  left_start: i64 = 0, left_end: i64 = 0,
  operator_start: i64 = 0, operator_end: i64 = 0,
  right_start: i64 = 0, right_end: i64 = 0,
  callee_start: i64 = 0, callee_end: i64 = 0,
  form: i64 = 0, left_kind: i64 = 0, left_literal: u32 = 0,
  right_kind: i64 = 0, right_literal: u32 = 0,
  callee_id: i64 = 0, depth: i64 = 0
}
struct Module { source: u8[] = [], declarations: Declaration[] = [] }
```

All spans are half-open UTF-8 source byte offsets. Declaration and expression
end exclude following comments/newlines; for calls expression span includes the
callee through `)`, and left span is the argument atom. `form=1` is atom,
`form=2` is bitand, `form=3` is direct call. Each atom kind is 0 for the
parameter and 1 for a literal, whose `u32` stores exact bits. Unused literals,
right fields, operator fields and callee fields are zero. `callee_id` is the
zero-based declaration-table index; zero is a valid call target and is absent
only for non-call forms. For call forms, `operator_start/end` are zero and the
callee span names exactly the resolved declaration. `return_start` names the
outer `return`; expression starts at left atom for atom/bitand, at callee for
call. All fields are immutable after successful independent validation.

Status values are 0 success, 1 `k1_syntax` (including duplicate declarations),
2 `k1_unsupported_feature`, 3 `k1_unbound_name`, 4 `k1_missing_return`,
5 `k1_source_limit`, 6 `k1_bad_control_target`, 7 `k1_type_mismatch`,
8 `k1_recursive_call`, and 9 `k1_resource_bound`. Preserve exact offending
spans in a future diagnostic layer; this prototype API has only a status.

## Resolved Core and callable resources

The dependency-free module Core namespace is `module_core`, separate from the
existing v2 scalar model:

```text
struct Value {
  producer: i64 = 0, type_id: i64 = 0, op_id: i64 = 0,
  literal: u32 = 0, left_id: i64 = 0, right_id: i64 = 0,
  callee_id: i64 = 0
}
struct Function {
  declaration_start: i64 = 0, declaration_end: i64 = 0,
  name_start: i64 = 0, name_end: i64 = 0,
  function_start: i64 = 0,
  parameter_start: i64 = 0, parameter_end: i64 = 0,
  return_start: i64 = 0,
  expression_start: i64 = 0, expression_end: i64 = 0,
  left_start: i64 = 0, left_end: i64 = 0,
  operator_start: i64 = 0, operator_end: i64 = 0,
  right_start: i64 = 0, right_end: i64 = 0,
  callee_start: i64 = 0, callee_end: i64 = 0,
  depth: i64 = 0, frame: i64 = 0,
  result_type: i64 = 0, value_count: i64 = 0,
  values: Value[4] = [Value {}; 4],
  terminator: i64 = 0, result_id: i64 = 0
}
struct ModuleCore { source: u8[] = [], functions: Function[] = [] }
```

The functions array is declaration order and its index is the owner-local
function ID. It is not the stable semantic declaration identity: that identity
also includes package, module path and declaration name. Type tag 1 is U32;
value producer 1 is parameter (always value ID 0), 2 is U32 constant, 3 is
binary operation, 4 is direct call. A value ID of 0 denotes the parameter;
unused input fields also contain zero and are interpreted by the producer tag.
Op ID 1 is `k1.u32.bitand.v1`, all other binary op IDs are unavailable here.
Allocate constants in left-to-right source occurrence order; append the binary
or call result last. A call result has producer 4, type 1, `left_id` the earlier
U32 argument value, exact selected `callee_id`, and zero op/literal/right input.
Other producer variants must have `callee_id=0`. `terminator=1` means explicit
return of `result_id`; all unused fields and values at/after `value_count` are
zero. No dead/extra values, second parameter, hidden operation or implicit
conversion is allowed.

Callees and signatures are resolved before body sealing. All callables have
empty effects/captures/preconditions and `frame=0` for this subset. The exact
private inferred `depth` is 1 for a leaf and 1 plus the callee depth for a
caller. Reject a cycle with `k1_recursive_call` and any depth above 128 with
`k1_resource_bound`. Depth is bounded K1 call nesting, not a claim about actual
engine/JIT/native stack bytes; the host must meet its separately stated engine
envelope. Each body completes once per declaration, and lowering consumes the
completed graph without general inference or legacy fallback. A compiler phase
counter must establish that claim before it is reported as qualified.

`module_frontend::to_core(module: Module&) -> module_core::ModuleCore` converts
a verified frontend Module into a ModuleCore, copying source and span fields
and constructing canonical typed values; it returns an empty Core if source
validation fails. That builder is not independent validation.
`module_frontend::verify_core(module: Module&, core: module_core::ModuleCore&)
-> i64` independently verifies the frontend source/graph, validates Core
structure, compares exact source bytes, spans and operations, and returns 0
only for an exact match. It returns 1 on failure. The independent validator must check grammar/source
correspondence, declarations and exact name resolution, uniqueness, result
signatures, all tags/fields/spans, dominant operands, graph/cycle and resource
summaries again before sealing. No supplied hash, header or executable payload
substitutes for this validation. Source-based fixture APIs do not establish
portable CheckedInterface/CheckedFunction artifacts.

## Backend seam

`wasm_v3::emit_module(core: module_core::ModuleCore&) -> u8[]` is an internal
fixture emitter and returns an empty array on malformed structural input. Call it
only after independent source/Core validation. It must defensively validate
all counts, indices, tags, types, resource bounds and spans before indexing or
slicing, emit one body per declaration, and preserve existing fixed memory
geometry. Each canonical callable is `(environment:i32, argument:i32) -> i32`.
For a direct call, emit `i32.const 0`, the already evaluated argument exactly
once, and `call` of the recorded owner-local target index. Test-only exports for
private declaration names are instrumentation, not K1 public exports. No
external executable bytes are trusted; the emitter regenerates code.

## Boundaries and laws

The experimental source Module, Core and Wasm module are not the normative
portable artifacts, ABI manifest, structural certificate, or host bridge.
No v3 serialized format is defined or admitted; SC01/SC02 must not be silently
reinterpreted as v3. Require positive and negative executable tests for
forward/backward calls, shared callees, literal and parameter arguments, both
U32 boundary values, missing/shadowed names, duplicate declarations, direct and
mutual recursion, depths 128/129, 256/257 declarations, out-of-range spans and
IDs, forged targets/resources/fields, and all unused declarations. Model-vs-Wasm
differentials and one-body-per-declaration checks are required before claiming
the connected fixture. K1-02 and the broader K1 rollout remain incomplete.

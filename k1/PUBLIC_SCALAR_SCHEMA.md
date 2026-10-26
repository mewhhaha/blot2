# Proposed public scalar declaration contract

This is a review proposal for a narrow K1-00 implementation slice. It does
not change source admission, define a portable artifact, authorize a host export,
or claim K1-00 complete. Normative authority remains [K1-LANG #40](https://github.com/mewhhaha/blot2/issues/40),
[K1-CORE #38](https://github.com/mewhhaha/blot2/issues/38),
[K1-MEM #41](https://github.com/mewhhaha/blot2/issues/41) and
[K1-EXEC #39](https://github.com/mewhhaha/blot2/issues/39).

## Exact initial source subset

A module contains one top-level public, noncapturing function. The initial
implementation accepts a one-physical-line declaration header in this form:

```text
pub let name: U32 -> result ! {} resources {depth: D, frame: S} = fn parameter => body
result := U32 | Bool
body   := return expression
        | do: newline INDENT return expression DEDENT
expression := scalar_expression
            | do: newline INDENT break scalar_expression DEDENT
            | do: newline INDENT return scalar_expression DEDENT
scalar_expression := atom | atom & atom | atom < atom
atom   := parameter | decimal_u32
```

The value `do` in this subset contains one `break` followed by an atomic or
one-operator expression; alternatively it may contain `return` of that
expression, which exits the function. A function-body `do` is not a value
block. A `return` operand may be such a value block, including inside the body
suite. Each physical suite begins exactly two spaces below its header. `D` and
`S` are unsuffixed decimal U32 literals. The existing language rules apply to
comments, CRLF, UTF-8, token boundaries, identifiers and reserved/builtin names;
all accepted tokens and node spans are byte offsets into the original source.
There is no implicit final-expression return. Other valid K1 syntax, including
line-wrapped declaration headers, additional declarations, public generics,
explicit callable `Fn[...]` spellings, contracts, calls, captures, other
operators, Bool input/literals and F32, is initially reported unsupported.
The broader language and its grammar remain unchanged.

Examples in the accepted subset:

```blot
pub let identity: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x

pub let less: U32 -> Bool ! {} resources {depth: 3, frame: 64} = fn x => return x < 7

pub let mask: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:
  return do:
    break x & 255
```

`U32 -> result` is the specified shorthand for a static-lifetime Many callable.
The explicit empty effect clause and both closed numeric resource fields are
required on a public declaration. Optional fact clauses can be omitted under
K1-LANG; the prototype rejects even well-formed explicit clauses rather than
silently discarding them. Similarly, a syntactically valid nonempty effect
upper bound is outside this slice and must not be silently treated as empty.
A private `let` continues to use its existing separate path.

`name` and `parameter` must be valid ASCII identifiers and cannot rebind a
reserved word or built-in. A parameter reference must resolve to this function's
parameter. A decimal integer must fit U32. An atom or `&` has result U32;
`<` takes two U32 operands and yields canonical Bool. The declared result must
match the expression. Evaluation is left to right and each operand is evaluated
once. Operators are the closed intrinsics described by the scalar registry;
there is no implied overload resolution, wrapping addition or implicit cast.

## Explicit resources and visibility

A declaration's `D` is a closed U32 satisfying `1 <= D <= 128`, and `S` is a
closed U32 upper bound in bytes. The admitted leaf bodies have measured
conservative requirements `{depth: 1, frame: 0}`: no captures, aggregate slots,
placements, calls or K1 linear-memory frame temporaries. The declared bounds may
be wider, so admission requires actual depth and frame to fit the declared
bounds; do not rewrite a public `{depth: 3, frame: 64}` interface to `{1, 0}`.
A missing effect or resource clause is an incomplete public interface. A
syntactically malformed resource record is a syntax error. A specified depth
outside 1..128 is a resource-bound error. The target profile and export wrapper
must separately establish that the declared frame allowance can be preflighted
against its selected fixed frame arena. Engine/JIT/native stack capacity is a
separate host-envelope assumption, not part of `S`.

`pub` exports the declaration from its source module for K1 import/linking. It
does **not** by itself define a host-facing export or the copy-only host bridge.
The implementation must publish a complete interface with source visibility,
producer identity (package, logical module path and declaration path), complete
argument/result, effects, callable mode/lifetime, capture, pre/postcondition,
resource and ABI information before another module can consume it. The initial
single-module fixture does not establish imports, portable interface artifacts,
linking or a host bridge. Fixture-only Wasm exports may expose the callable for
execution tests but are not an implemented public host protocol.

## Candidate representation and independent checking

Use a distinct public-declaration wrapper around the checked scalar body; do not
infer visibility from an export name or reuse a private scalar header as a
complete public interface. It must own or identify the exact immutable source,
retain source-origin spans for `pub`, the name, types, effect clause, resource
keys/values, parameter and body, and record:

- edition `k1`, the exact K1 semantic/optimization policy and ABI identities;
- visibility public; U32 argument and U32 or Bool result, Many mode, static
  lifetime, no capture footprint, empty explicit effect upper bound and empty
  pre/post/Boolean contracts;
- the declared resource upper bounds, separately from the computed actual
  leaf requirements, plus the selected body operations and exact lexical exits;
- stable producer identity and the complete fields required by K1-CORE for a
  checked interface/function and its target-specific LoweringPlan.

Until those owned artifacts, hashes, origin ownership, and independent
validator exist, a source parse result is only a candidate and must not be
published as a completed public interface. In particular, current local scalar
records and a test-only export do not by themselves satisfy that boundary.

An independent source recognizer must read the original bounded UTF-8 source,
not a frontend success flag, and check the complete token stream, `pub let`,
identifier and parameter binding, callable annotation and result, explicit
empty effect clause, resource key order and exact decimal values, source spans,
body expression, operator identity, lexical return/break targets, indentation,
and end of source. It must reject duplicate/unknown fields, an omitted clause,
extra operations, unconsumed tokens and mutated header/body bytes. Validate all
spans and arithmetic before slicing or allocating. Independently validate the
owned Core and interface, exact selected scalar operations, result types,
effects/captures and every exit; recompute the actual resource lower bound and
check it against the *declared* bounds. Do not trust frontend-selected result
types, a precomputed proof bit, optimizer output or a locally assigned numeric
ID as authority. Required checking and static work precede semantic sealing;
no general inference or legacy specialization fallback may occur afterward.

When lowering is separately qualified, `K1-WASM32-ABI1` uses the canonical
noncapturing callable `(environment:i32, argument:i32) -> i32`, environment
zero. U32 returns its exact bits and Bool returns exactly 0 or 1. Publication
requires the full compatible ABI hash, memory map, helper-role checks and
structural certificate; a correct scalar instruction stream is not sufficient.
No required proof, resource or visibility obligation may depend on optional
optimization. The scalar public path does not admit the private `x + 0`
experiment until its own evidence, work charging and source-to-plan gates are
integrated under a separately reviewed contract.

## Prototype diagnostic mapping

These are isolated frontend statuses, not new portable diagnostic IDs. A
successful candidate is status 0. Status 1 maps to `k1_syntax` for malformed
lexical/grammar/indentation or an out-of-range U32 literal; 2 to
`k1_unsupported_feature` for valid constructs outside this initial subset; 3 to
`k1_unbound_name`; 4 to `k1_missing_return`; 5 to `k1_source_limit`; 6 to
`k1_bad_control_target`; 7 to `k1_type_mismatch`; 8 to
`k1_incomplete_interface`; and 9 to `k1_resource_bound`. An internal mismatch
between the producer and independent validator is a compiler error and must not
be disguised as an accepted declaration or silently retried through legacy.

A missing colon/type after `pub let` is malformed declaration syntax; omitting
the entire otherwise-optional effect or resources suffix leaves a syntactically
valid but incomplete public callable interface. An unsupported explicit
contract/effect is not an effect mismatch merely because this prototype does
not implement it. Invalid values inside the exact resource record are checked
before any output or host invocation.

## Acceptance and rejection laws

Before claiming this slice, exercise short, body-block and value-block explicit
returns, identity and constants, bitand and unsigned comparisons, both U32
boundaries, Bool 0/1, valid widened resource bounds, comments/CRLF and forged
header/body spans. Reject absent type, absent effects/resources, depth 0 and 129,
U32 literal overflow, wrong result type, unbound names, missing return, wrong
break target, unsupported effects/contracts, malformed resource syntax,
additional declarations and trailing code. Mutate every source-origin span,
visibility, producer identity, selected operation, result type, declared
resource and computed requirement; independent validation must fail.

Run the same source judgment with optimization disabled/enabled and ensure the
emitted Wasm agrees with a scalar reference. Test a widened declared bound
without silently narrowing its imported interface; reject incompatible edition,
semantic policy, ABI hash and forged headers before unsafe decoding. Record
actual pinned Goose/toolchain, native and executed-Wasm commands, counters and
repository gate evidence. The full K1 qualification, work accounting,
independent artifact validation and legacy fence remain required.

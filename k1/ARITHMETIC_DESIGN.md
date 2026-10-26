# Future slice: checked U32 addition by zero

This is a proposal, not implemented behavior or a change to the K1 contract.
The normative rules are [K1-LANG #40 §§8–9](https://github.com/mewhhaha/blot2/issues/40),
[K1-CORE #38](https://github.com/mewhhaha/blot2/issues/38), and
[K1-EXEC #39](https://github.com/mewhhaha/blot2/issues/39). The current proof
arena is disconnected and its assumptions are not source evidence. This slice
does not complete K1-03 or qualify public compilation.

## Exact admission boundary

Extend the existing private scalar fixture only for a single ordinary addition
whose left operand is the function's exact U32 parameter and whose right
operand is a decimal U32 literal:

```blot
let identity: U32 -> U32 = fn x => return x + 0
```

The supported body and value-block return forms should retain their existing
lexical targets. The result is U32 and evaluation remains left-to-right. This
slice recognizes no guards, additional local bindings, rebindings, nested
arithmetic, or extra parameters. Other valid K1 forms stay explicitly
unsupported until their complete semantics are implemented.

Within this boundary the addition is provable exactly when the right literal
has value zero. Every input is U32, so `x <= U32.MAX` always holds, and
`U32.MAX - 0` is `U32.MAX`. K1-LANG §9.2 rule 2 establishes
`AddFits(x, 0)` from `Le(x, U32.MAX - 0)`. A nonzero literal has no such
universal proof: with input `U32.MAX`, `x + k` overflows for every `k > 0`.
The compiler must report `k1_arithmetic_not_established` at the addition for
that recognized form, before plan construction or emission. It must not add a
runtime overflow trap, invoke wrapping addition, or rely on optimization to
make the program admissible.

`0 + x`, literal-plus-literal, and guarded `x + k` may be useful later, but
are outside this proposed slice. They must not acquire a proof merely from this
design. Literal-plus-literal needs an exact checked mathematical sum; a guard
needs its own correctly scoped branch fact, plus explicit control-flow and
join validation. No arbitrary user predicate or equal source spelling supplies
those facts.

## Proposed completed representation

Extend the private `ScalarCore` and its local operation registry in one
coordinated schema change. The exact field layout and local operation ID are
to be frozen before consumers change. A checked addition must represent:

1. The existing parameter value, its exact owner-local value ID, type U32 and
   provenance/version; a distinct U32 literal-zero value; and an explicit U32
   addition result with the exact two operand IDs. The terminator returns that
   result. The operator and operand spans are source origins, not proof by
   themselves.
2. An owned finite evidence DAG scoped to this function body. Its conclusion is
   `AddFits(parameter_value, zero_value)`, with exact value IDs and their
   owner/scope. It contains the U32 upper-bound axiom `Le(parameter_value,
   U32.MAX)`, a checked normalization of the exact complement term
   `U32.MAX - zero_value` to `U32.MAX`, and the K1 `AddFits` transfer using
   those prerequisites. A Boolean `proved` flag, a source string, or an
   unchecked assumption is insufficient.
3. Complete type, effect, use and resource information for the existing
   noncapturing scalar function, plus the versioned semantic policy and
   operation identity. The proof and operation are sealed before lowering;
   the backend cannot discover or repair missing proof by running inference.

The evidence representation may use other equivalent compact nodes, provided
each rule, conclusion, exact operands, scope and prerequisite IDs are explicit
and mechanically validated. K1 allows equality substitution only for compatible
sorts and checked provenance. A proof for a different SSA version, different
literal value, different function, or different operands is not transferable.
An ordinary `x + 0` remains an ordinary checked addition; it is not a wrapping
intrinsic and its proof is required even if a later rewrite removes the add.

## Independent admission and lowering

The frontend recognizes the full operand/operator sequence and reports syntax,
name and type errors before completion. Completion constructs the required
evidence or reports the appropriate required-proof diagnostic. A separate
validator must reject malformed spans and IDs before indexing; independently
check source-to-Core binding, types, operand order, the `+` operator, literal
value, operation identity and return target; then check each evidence rule and
its prerequisites without trusting the frontend or a cached success flag.
This includes acyclic earlier-node references and exact operand/scope matching.
Unused or extra records must follow a specified schema and may not conceal an
unvalidated operation. Validator failure is an invalid internal artifact, not
permission to try legacy checking.

The unoptimized lowering plan may emit the two U32 operands followed by Wasm
`i32.add` (`0x6a`), with the prior validated proof establishing that its modulo
machine operation equals K1's ordinary addition for all admitted inputs. The
existing scalar ABI passes the environment first and the U32 argument second;
the test wrapper uses environment zero. The emitter must check the selected
operation and plan as well as receive independently validated source/Core; it
must not accept a forged plan merely because the Wasm opcode is valid. No
fixed-memory, host-bridge, certificate, or general artifact qualification is
implied by this fixture.

The implementation must charge all required term and edge interning, proof
visits, substitutions, intrinsic attempts and evidence validation, including
helper traversal. The versioned per-declaration ceilings remain 4,096 proof
terms, 16,384 active fact/evidence edges, 65,536 charged proof visits and
1,048,576 total required semantic visits. Establish a deterministic receipt
for this slice with exact-at-limit and one-over tests; do not invent a separate
larger budget or let cache warmth, optimization level or worker ordering alter
admission. Optional optimization exhaustion retains a validated baseline.

## Required laws before connecting the slice

- Accept the three supported explicit-return forms of `x + 0`; independently
  validate evidence and execute emitted Wasm at inputs 0, 1 and U32.MAX. Check
  output bit patterns, the selected operation, and the unoptimized `i32.add`.
- Reject `x + 1` and `x + 4294967295` with
  `k1_arithmetic_not_established`, including the U32.MAX overflow witness;
  reject other unsupported arithmetic without producing a plan or bytes.
- Reject a missing `+` operand, out-of-range decimal, unknown operand name,
  wrong result type and malformed token/span using the applicable closed K1
  category. Test leading-zero literal spellings consistently with the lexer.
- Reject fabricated evidence with a missing or forward prerequisite, a cycle,
  wrong rule, wrong operand ID/value/version/scope, wrong complement, wrong
  conclusion, malformed table index or duplicated value ID. Independently
  mutate the operator, its source span, the literal, return result, ABI and
  selected lowering opcode. None may publish bytes.
- Verify required-work receipts and limit outcomes in check/build, baseline and
  optimized configurations, cold and warm paths and supported worker counts.
  This experiment cannot claim those laws until those modes actually exist.
- Sweep allocation/operation failure through construction and validation;
  failures leave the previous successful state intact and publish no partial
  artifact. Run the repository's applicable native and executed-Wasm gates and
  record toolchain, commands and exact outcomes.

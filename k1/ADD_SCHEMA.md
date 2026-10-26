# Private experimental scalar-addition schema v4

The separate `add-fixture` exercises this narrow interface. It does not alter
the existing scalar fixture, define a portable artifact, or qualify K1.
The normative target remains [K1-LANG #40](https://github.com/mewhhaha/blot2/issues/40),
[K1-CORE #38](https://github.com/mewhhaha/blot2/issues/38), and
[K1-EXEC #39](https://github.com/mewhhaha/blot2/issues/39). Implementers must
agree on the builder, validator and emitter interfaces before changing the v2
schema. See `ARITHMETIC_DESIGN.md` for the logical proof and outstanding laws.

## Scope and diagnostics

The only new accepted expression is the declared U32 parameter followed by `+`
and a decimal U32 literal whose value is zero, for example:

```blot
let f: U32 -> U32 = fn x => return x + 0
```

The previously supported explicit body/value-block forms must retain their
actual lexical return/break targets. For a recognized binary `+` expression,
all other operand combinations, including nonzero literals, another parameter
use, and constant-left expressions, report `k1_arithmetic_not_established`:
this private checker has not established the required fact for them. This is
not a claim that every rejected expression is mathematically unprovable. Other
unimplemented syntax retains `k1_unsupported_feature`. Lexical, binding and
type failures retain their applicable closed K1 categories and precede a proof
attempt. No rejected source publishes a plan or bytes.

## Proposed owned wrapper

Keep the existing `ScalarCore` layout as the embedded value representation and
introduce a distinct **in-memory-only** wrapper, here called `AddCoreV4`:

```text
AddCoreV4 {
  schema: 4, owner: 1, scope: 1,
  core: ScalarCore,
  evidence: add_proof::Proof
}
```

`owner` and `scope` are fixture-local identities chosen by the compile job,
not stable module IDs or authorization received from a caller. They are valid
only because this fixture permits one noncapturing declaration in one compile;
there is no import, artifact persistence, cross-function reuse or cache. Every
compile starts fresh and binds evidence to the independently checked current
source. A future multi-declaration or persisted implementation must replace
these fixture identities with the specified owned identity scheme, not assume
that every function or block is `1`.

The embedded `ScalarCore` has exactly this shape:

| Field | Required value |
| --- | --- |
| `result_type`, `terminator`, `result_id` | `1` (U32), `1` (return), `2` |
| `value_count` | `3` |
| `values[0]` | producer `1` (parameter), type `1` (U32); all other fields zero |
| `values[1]` | producer `2` (constant), type `1`, literal `0`; all other fields zero |
| `values[2]` | producer `3` (operation), type `1`, local `op_id=3` (checked U32 add), `left_id=0`, `right_id=1`, literal zero |
| `values[3]` | every field zero |

Local `op_id=3` is an implementation fixture identity, not a new normative
K1 operation ID. Its registered contract is two U32 operands, U32 result,
required `AddFits(left,right)`, no effects or ownership transition, no implicit
failure or wrapping semantics, and an unoptimized `i32.add` realization only
after validation. Previous v2 entry points must continue to reject this new
operation; do not let a v2 structure or emitter silently accept op 3. Exact
schema/operation checks prevent substituting an `and` or `<` plan.

The function is a single immutable straight-line fixture. Its version mapping
is **derived**, not trusted input: value ID 0 has version 1, ID 1 version 2,
and ID 2 version 3. The independently reconstructed `add_proof::Subject` is:

```text
owner=1, scope=1,
parameter=0, parameter_version=1,
zero=1, zero_version=2,
result=2, result_version=3,
zero_literal=0, operation=1
```

The `operation=1` here is the local `add_proof` subject tag; it is distinct
from Core `op_id=3`. Validator code derives the subject from the checked Core
shape and compile-job identity, then checks every term/node and prerequisite
in the embedded proof against it. It must not copy the expected subject from
the proof itself. The mapping is sufficient only for this immutable three-value
fixture and must not be reused for general SSA, branch merges, or cross-owner
substitution.

## Source and proof validation

Keep the existing half-open `name`, `parameter`, `left`, `operator` and `right`
byte spans in the embedded Core. Check every bound before slicing and validate
the 16 MiB limit and UTF-8 before lexing. An independent recognizer must verify
the complete source form and lexical target, declaration name and function
parameter, the left operand's exact binding to that parameter, a single `+`
operator at its recorded span, and the right decimal literal's checked U32
value of zero at its own recorded span. It must reject extra operations or
unconsumed source, including a changed suffix. The source recognizer and Core
validator must not call the frontend to repeat its answer. The owned syntax
snapshot/parser must also recognize the new token and independently agree with
the same source, or the feature remains unadmitted.

Completion constructs the subject only after a source/Core candidate is known,
then calls `add_proof::build` using the compile job's own `Work`. After attaching
the proof, the independent v4 validator rechecks source-to-Core correspondence,
the entire exact Core shape, owner/scope and schema, reconstructs the subject,
and calls `add_proof::validate` with that same `Work`. The `Le(parameter,MAX)`
axiom, exact `MAX - 0` normalization and `AddFits` transfer are checked as
explicit earlier-node prerequisites; changed rule, operand, version, scope,
literal, result, link or conclusion invalidates the fixture. No `proved` bit,
validated stamp, cached response, serialized `Work`, or source-name coincidence
is accepted as evidence.

## Plan and emission seam

The proposed `AddPlanV4` owns an `AddCoreV4` **by value**, schema `4`, edition,
semantic/optimization policy, ABI identity, scalar parameter/result
representations, first environment parameter, resource bounds and the exact
opcode `0x6a` (`i32.add`). Fixture geometry and no-helper fields are checked as
they are for the existing scalar plan. A source-independent shape check alone
does not establish that the proof belongs to the source.

The plan validator checks every plan field and the copied Core and proof. The
emitter's proposed interface receives the original source, the by-value plan,
and the same compiler-owned declaration `Work`; before writing any output it
independently reruns source/Core/evidence and plan checks. It emits local-get
of the argument, i32.const zero, i32.add, return/end using the current scalar
Wasm ABI. Output is built privately and published only after the complete
validation and encoding succeed. A machine opcode, an earlier frontend result,
or a plan stamped “checked” is never authority. The code-generation body may
not silently replace the operation with wrapping behavior or depend on an
optional optimizer; a separately validated later rewrite may remove it.

Avoid legacy paths accepting `op_id=3`: v2 validation, v2 plan creation and v2
emission each reject it. Conversely, a v4 plan with a v2 schema, a wrong policy
or ABI, a wrong opcode, an absent proof or changed source is rejected before
emission. There is no portable cache/import in this slice; a future cache must
carry policy IDs and replay the required logical work and independent checks.

## Work accounting and blockers

`add_proof::build` charges four terms, five fact/evidence records/links and ten
proof/semantic visits for the fixed proof. Its validator charges ten further
proof/semantic visits against the **same** compiler-owned `Work`; each repeated
validation must charge again. Other lexer, syntax, Core, source-recognizer,
plan and emission traversals must also charge the shared total semantic budget.
The full K1 ceilings remain 4,096 terms, 16,384 fact/evidence edges, 65,536
proof visits and 1,048,576 total semantic visits per declaration.

The standalone meter returns status 2 for proof term, edge or visit exhaustion
and status 3 for the total semantic ceiling. `Work.limit_quantity` identifies
terms (1), edges (2), proof visits (3), or total semantic visits (4). If both
ceilings are exhausted, it reports semantic exhaustion first. An integration
must translate these to `k1_proof_limit` and `k1_semantic_limit` and report the
applicable quantity and measured count.
Fixed owner/scope values and mutable numeric Work counters cannot establish
cross-compile provenance, including replay with a separately charged Work.
The private driver creates its own Work and does not accept cached proofs, but
that convention is not an independently authenticated job identity. The rest
of the fixture does not yet charge a shared semantic traversal budget.
Before this can be described as K1-policy-complete, a shared declaration meter must
cover every required traversal and preserve the same acceptance and logical
charges across cold/warm, check/build, optimization levels and worker counts.
The fixed proof counts above are local measurements, not evidence of that full
meter. Do not claim K1-03 or expose public K1 admission while this remains open.

## Review gates

- Positive laws execute the three supported explicit-return forms with inputs
  0, 1 and U32.MAX, validate the evidence independently, and inspect the
  unoptimized addition opcode and operands.
- Reject recognized `x + 1`, `x + 4294967295`, `x + x`, and constant-left
  additions with the specified private-slice diagnostic and no output. Test
  syntax/name/type errors separately, including trailing operators and overflow
  in the decimal lexer.
- Mutate each source span, source token, Core slot, ID, owner, scope, derived
  version, proof term, rule, prerequisite, conclusion, local operation ID, plan
  schema, ABI and opcode; each must be rejected. Include changed source with a
  reused proof, cross-compile replay and an uncharged fresh `Work`.
- Test exact and one-over proof and semantic limits, repeated validations,
  interrupted construction and failed publication. Check the applicable
  no-fallback CLI behavior; record actual commands and toolchain rather than
  reporting anticipated tests as executed.

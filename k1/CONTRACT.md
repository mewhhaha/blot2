# K1 Goose scalar prototype contract

This is a narrow implementation contract for the first Goose-based experiment,
not a replacement for [issue #37](https://github.com/mewhhaha/blot2/issues/37)
or its four normative parts: [CORE #38](https://github.com/mewhhaha/blot2/issues/38),
[EXEC #39](https://github.com/mewhhaha/blot2/issues/39),
[LANG #40](https://github.com/mewhhaha/blot2/issues/40), and
[MEM #41](https://github.com/mewhhaha/blot2/issues/41). The target is K1 revision 1;
this document does not claim K1-00 or the full edition is complete.

## Identity and admission

The mandated identifiers are `K1-SEM-POLICY-1`, `K1-OPT-POLICY-1`, and
`K1-WASM32-ABI1`. K1 requires explicit `--language=k1` selection; the existing
legacy edition remains default. Unknown editions and incompatible artifacts must
be rejected before lowering, and no K1 source may fall back to the legacy
compiler or its managed runtime. Request configuration, project metadata and
every artifact key/header eventually carry the relevant edition and policy/ABI
identities. No experimental in-memory struct or standalone Wasm module is a
completed K1 artifact or a substitute for the required header, ABI hash,
independent validator, or structural certificate.

The experiment recognizes exactly one private, noncapturing declaration:

```text
let name: U32 -> U32 = fn parameter => return operand
let name: U32 -> U32 = fn parameter => do:
  return operand
let name: U32 -> U32 = fn parameter => return do:
  break operand
operand := parameter | decimal_u32
```

`name` and `parameter` are ASCII identifiers per LANG section 2, excluding
reserved words and builtins; the identifier operand must resolve to the single
parameter. `decimal_u32` is an unsuffixed decimal integer in 0..4294967295.
The header is restricted to one physical line. Suites use exactly two spaces per
level; blank lines and `//` comments are permitted. A body `do` may return a
value `do` with `break operand`; a value `do` may also contain `return operand`,
which exits the enclosing function directly. A body ending in an expression
without `return` is `k1_missing_return`; `break` or `continue` without a valid
lexical target is `k1_bad_control_target`; an unbound operand is
`k1_unbound_name`; malformed grammar is `k1_syntax`. Valid K1 constructs not
implemented in this experiment are rejected as `k1_unsupported_feature`;
never accept them with altered meaning. No arithmetic, control flow, imports,
collections, closures, generics, public exports, general blocks, effects, static
initializers or host array bridge are claimed. In particular, arbitrary U32
arithmetic cannot be lowered as total: ordinary operations require the exact
proofs in LANG section 8.

## Shared frontend/emitter seam

The initial transient frontend interface is `frontend.parse_scalar(source:
u8[:]) -> ParseResult`, with owned scalar fields `status: i64`, `kind: i64`,
`literal: u32`, `start: i64`, `end: i64`, `name_start: i64`, and
`name_end: i64`. Offsets are half-open UTF-8 byte positions into the original
source; the record holds no borrowed source pointer. `status` is 0 on success,
1 `k1_syntax`, 2 `k1_unsupported_feature`, 3 `k1_unbound_name`, 4
`k1_missing_return`, 5 `k1_source_limit`, and 6 `k1_bad_control_target`.
On success `kind` is 0 for the
parameter and 1 for a constant; `literal` is meaningful for kind 1. Other status/kind values are
invalid. A consumer validates source length, offsets, name spelling, kind, and
all invariants before using spans or emission. ParseResult is not a durable
CheckedFunction, and accepting a forged result is never evidence of source
admission.

The transient structural validator `validate::scalar` checks identifiers,
operand bytes, literal values, enum tags, spans and policy strings before emission.
It independently recognizes the narrow admitted grammar and checks the proposed
operand and declaration name against the source. It does not validate general
Core or serialized artifacts; those independent checks are still required.

The internal Wasm fixture emitter seam is `wasm::emit_scalar(name: u8[:], kind:
i64, literal: u32) -> u8[]`. Its caller must run source completion and separate
validation first; emitter kinds are 1 for the parameter and 2 for a constant,
so the driver translates frontend kinds only after validation. The emitter rejects
invalid kinds/names by returning an empty array. Its fixture-level
export name exposes the private test callable to the test engine, not a claim
that the full K1 public interface or host bridge is implemented.

For coordination the local subset operation identifiers are
`k1.u32.parameter.v1`, `k1.u32.constant.v1`, and `k1.return.v1`. These are
implementation-local names, not additional identifiers specified by the issue.
Both operand kinds are pure, total, and non-generative; their U32 result is
Plain and Share, and the only terminator returns that value. The private leaf
has empty effects and synthesized `resources {depth: 1, frame: 0}`. There are
no captures, calls, borrowed values, failure transitions, or backing storage.
An expanded operation registry must specify each operation's schema, effects,
preconditions, ownership/initialization transitions, failure, target feasibility
and lowering; new features are not admitted by assigning them a name alone.

## Phase and ABI boundary

The required overall order is parse/name resolution; completion (type, effects,
usage, resource and required proof checking); required static evaluation;
sealing and independent validation; transactional semantic publication; optional
optimization; validated lowering and runtime-role/helper checks; encoding and
atomic revision publication. The scalar fixture has no required static work or
rewrites, but trace slots for completion, static evaluation, validation,
optimization and lowering must identify them as completed or skipped accurately.
A trace cannot substitute for the validation itself. No new general inference
may occur after semantic sealing; missing information is a compiler error, not a
reason to fall back or infer again.

The subset's canonical `K1-WASM32-ABI1` callable has `(environment: i32,
argument: i32) -> i32`. A noncapturing callable receives environment zero;
U32 passes and returns its exact 32-bit pattern. A test harness may call that
entry with zero environment. The fixture must not imply that this alone
establishes the mandatory fixed linear memory and full memory manifest, ABI hash, bridge, frame
preflight, or no-managed-helper certificate. K1's full target uses fixed Wasm32
memory with no `memory.grow`, no tracing/cycle collector, no per-value RC/ARC,
no hidden shared owner or implicit closure box; storage and ownership must be
checked independently of optimization.

## Required qualification, still pending

K1-00 requires an executable scalar compile-and-run fixture, positive and
negative native/guest laws, unsupported syntax diagnostics, edition mismatch and
forged-header rejection before unsafe decoding, fixture inventory and phase
trace. Later stages introduce the complete syntax and formatter/editor,
independent owned artifacts, proofs, scoped pool and particle loop, relational
graphs, closures and finite resources, whole-region Owned and copy-only host
bridge, generics/static evaluation, optimizer/reuse/transactions, then the full
rollout gate. Required budgets, operation/version changes, and semantic evidence
follow the linked specifications; none is waived by this prototype.

# Proposed K1 required-work accounting

This is an implementation design, not a claim that the current fixture enforces
the complete policy. The normative limits and phase rules are in
[K1-CORE #38 §§C06–C09](https://github.com/mewhhaha/blot2/issues/38),
[K1-LANG #40 §9](https://github.com/mewhhaha/blot2/issues/40) and
[K1-EXEC #39](https://github.com/mewhhaha/blot2/issues/39). K1-00 is not
complete until the actual parser, source checks, Core, proof, plan and required
validation paths share and test the accounting described here.

## Ownership and limits

A compile job owns one mutable `DeclarationWork` for each declaration in its
immutable source snapshot. It is created once and passed by mutable reference
through all **required** phases; no phase creates a fresh meter for the same
declaration. The private one-declaration fixture has one owner, so it needs no
cross-worker allocation of a shared budget. Counts and operation IDs below are
proposal fields, not an externally callable or serializable protocol.

| Field | Required limit | Failure category |
| --- | ---: | --- |
| `semantic_visits` | 1,048,576 | `k1_semantic_limit` |
| `proof_terms` | 4,096 distinct terms | `k1_proof_limit` |
| `proof_edges` | 16,384 active facts/evidence edges | `k1_proof_limit` |
| `proof_visits` | 65,536 | `k1_proof_limit` |
| `core_operations` | 65,536 including terminators | `k1_core_limit` |
| `core_blocks` | 4,096 | `k1_core_limit` |
| `type_nodes` | 8,192 | applicable K1 required-limit diagnostic |
| `type_nesting` | 64 | applicable K1 required-limit diagnostic |
| `generic_binders` | 32 | applicable K1 required-limit diagnostic |
| `static_steps`, `static_depth`, `static_bytes` | 100,000, 128, 4 MiB | `k1_static_limit` |

Schema validation must choose the exact closed diagnostic category for each
type or binder limit before that language feature is implemented; the table
does not invent new diagnostic categories. Source bytes, syntax nesting,
modules and import edges use their separate `k1_source_limit` rules: 16 MiB per
module, nesting 64, 4,096 modules and 65,536 import edges. The byte ceiling is
checked before source allocation/scanning and before a dependent byte read.

The meter also owns bounded per-phase aggregate counters for tracing and a
`failure { category, quantity, measured, limit, declaration, origin }`. Origin
is a checked source span where available. Counters and traces are private owned
data: they contain no allocator pointers, solver IDs or externally supplied
receipts. No untrusted artifact or host input may set the counters.

## Charge operations

Proposed APIs take an owner-local meter and a closed event kind:

```text
semantic_visit(kind, origin)              // one required semantic node/edge
proof_visit(kind, origin)                 // one proof + one semantic visit
intern_term(is_new, origin)               // proof visit; +1 distinct term iff new
add_fact_or_evidence_edge(origin)         // proof visit; +1 active edge
check_source_limit(bytes, nesting, ...)    // separate source policy
record_source_byte_read(phase, offset)    // bounded-work telemetry, not a new limit
static_step / enter_static / static_bytes // required-static policy
```

`semantic_visit` charges one unit before each actual AST, Core, type, effect,
usage, exhaustivity, layout or constraint node **or edge** visited, including
helper traversals and repeated visits. A newly materialized semantic node and
each later visit are distinct events. Parser token records consumed for
constructing or verifying an AST are semantic visits under this proposed
fixture schedule; a token revisited by another required pass is charged again.
Reading multiple scalar fields while examining one record is one record visit;
following another record ID or edge is another visit. Decisions that do not
visit another node/edge are not silently turned into unbounded helper loops.
The event catalogue and traversal order must be frozen with the implementation,
so refactoring or a cache cannot silently change the receipt.

Every proof term lookup/probe, equality substitution, edge examined, intrinsic
rule attempt, evidence node and prerequisite edge validation is a `proof_visit`
and therefore also one `semantic_visit`. Successful first insertion of a term
also increments `proof_terms`; a reused term does not, but its lookup/probes
still charge. Each published fact or evidence edge, including prerequisite
links, increments `proof_edges`. A fact may leave the active count only after
its lexical scope and every dependent evidence reference have been discharged;
the check must prevent stale IDs from regaining authority. Peak active count
and total visits remain in the receipt. Distinct-term accounting is per
declaration, not per scratch arena reset.

Charge **before** each event and before publishing the associated mutation.
Each charge tests its requested increments with subtraction-based bounds,
without overflowing, then atomically updates all applicable counters. The
event that would exceed a ceiling is not performed and does not increment its
counts. If the total semantic ceiling and a proof ceiling would both fail on
the same event, report `k1_semantic_limit` and its measured quantity; otherwise
report the specific failed limit. A value exactly equal to its limit is valid
after the last successful charge; the next requiring an increment fails. A
multi-event construction may have spent earlier work when a later event fails,
but it must publish no partial proof or artifact. Discard that failed job's
private state; do not reset its counters and continue the same obligation.

## Source bytes and parser attribution

The 16 MiB limit is an input ceiling. C09 explicitly charges semantic
AST/Core/type/effect and related node/edge visits, including helper loops; it
does not specify that every raw byte read consumes one semantic visit. Do not
silently impose a one-byte-per-semantic-visit rule: that would make a long
comment fail near 1 MiB even though it creates no corresponding AST nodes.

Record source scanning separately. For the fixture, `source_byte_reads` counts
one for each logical byte inspection, including lookahead and repeated scans,
in a fixed phase counter. The bounded reader first enforces the byte ceiling;
UTF-8, lexing, the independent source recognizer and any required recheck have
explicit bounded passes over that immutable buffer. Each pass must have a
documented input-derived bound, checked offset arithmetic and no repeated path
enumeration. Repeated source scans are recorded; they do not evade a semantic
charge when they also visit AST/Core or proof records. A `u64` telemetry counter
is checked for overflow, which is an internal accounting error, not a new
source admission limit.

The exact relation between raw byte-helper iterations and the semantic total is
not otherwise specified by the handoff. This design records that distinction
and does not amend K1-SEM-POLICY-1. If later interpretation requires charging
individual raw bytes to the semantic ceiling, resolve the acceptance impact
and policy/key version explicitly before changing behavior. Test long comments,
tokens and UTF-8 near 16 MiB as well as dense AST inputs near the semantic
limit; do not infer that every file below the byte cap must pass all other
independent checks.

For the first fixture all lexical and syntactic records belong to its sole
declaration. A complete module implementation still needs a reviewed,
deterministic rule for assigning token/AST visits around imports, comments and
shared module setup to declarations, including source with no declarations.
Do not charge the entire module afresh to every declaration or allocate a shared
remaining semantic budget by worker completion order. Until attribution and
multi-module laws exist, this document does not claim complete project support.

## Required phase schedule for the private fixture

The fixed schedule is the same regardless of code-generation tier, cache state
or worker count. Count every invocation, including independent rechecks:

1. Bounded read and complete UTF-8/lexical validation record byte scans and
   source limits; token production and syntax construction charge the declared
   token/AST events. Source diagnostics never fall back to legacy checking.
2. The independent source recognizer and owned parser visit their own tokens,
   syntax nodes and child edges. The typed-Core builder visits input nodes and
   records each created value, type, operation and explicit return terminator.
   Independently validating source-to-Core binding repeats and charges those
   visits; a parser result or source span is not authority by itself.
3. Completion performs type, operation, effect, usage, resource and required
   proof checks. For the proposed `x + 0` proof, the present standalone builder
   charges four term insertions, five evidence records/links and ten visits;
   its independent check charges ten more visits on the same job's `Work`.
   Those numbers cover only that isolated proof, not the surrounding frontend.
4. Required static evaluation is explicitly absent or runs with its own limits.
   Seal completed semantic data, prohibit downstream general inference, and
   validate the owned semantic record independently. No publication happens
   merely because a trace says a phase ran.
5. Build and check the target plan with explicit Core/representation/ABI and
   evidence visits. Any mandatory proof or source/Core revalidation is charged
   again. In the private emitter this includes its immediate recheck. Admission
   is not published until these fixed required checks succeed; a successful
   proof cannot acquire free work by being wrapped in another plan.
6. Optional optimization uses its separate `K1-OPT-POLICY-1` counters. Optional
   budget exhaustion declines the rewrite and retains the already validated
   baseline; it never changes a source verdict or increases required limits.
   Mandatory checks whose result affects admission must not vary by tier.
   Encoding/structural target validation remains bounded and cannot launch
   inference. A malformed newly produced plan or executable is a compiler
   error, not a recoverable source proof or a cache hit.

An implementation must decide exactly which checked target validation visits
belong in the required pre-publication schedule and how their bounded target
work is separately metered. It must not charge optional, release-only rewrites
against the source's required semantic budget or report an already admitted
source as unsafe merely because an optional candidate exhausted its own budget.

## Receipts, caches, parallelism and failure

The trusted completion process seals an immutable receipt with the policy ID,
source/owner identity, declaration identity, ordered phase schedule, category
counts, final totals, limits and exact dependency observations. A hash is only a
candidate lookup; exact supported comparison and source/dependency admission
still apply. A warm result must represent the same required logical work as a
fresh check. An untrusted disk/imported receipt cannot assert a cheaper history:
recheck source under the same policy before promotion, or validate a required
source-less Core as a distinct artifact input without claiming fresh-source
parity. Cache decline, corruption, saturation and optional rewrite failure fall
back to valid fresh/baseline work, never a larger required budget.

Parallel workers own independent declaration meters and immutable dependencies.
Schedule completion, dependency observations and publication in deterministic
acyclic order; worker timing cannot decide which declaration receives the last
unit of a global budget. Merge only complete validated results. A cancelled or
OOM attempt returns no proof, plan or partial revision, frees its private owners
and leaves the last successfully published revision usable. OOM is reported as
an allocation failure, not a semantic-limit proof. A fresh retry recomputes
its deterministic receipt rather than inheriting untrusted partial counts.

## Required tests before claiming integration

- Exact-at-limit and one-over cases for every required quantity, including a
  charge that would exceed semantic and proof limits together; assert the
  selected category, quantity, unchanged failed-event counters and source
  origin. Verify cumulative charges across frontend, proof and revalidation.
- Equal input in check/build, unoptimized/optimized, cold/warm and all supported
  worker counts must have the same source verdict and required logical receipt;
  run repeated validator calls and show each is charged. An optional optimizer
  exhaustion retains the already validated baseline.
- Cover valid long comments and UTF-8 near the byte ceiling, over-limit input
  rejected before scanning, deep/numerous AST nodes, token/AST re-visits and
  parser helper loops. Verify byte telemetry separately from semantic visits.
- Reject forged counters, cheap cache receipts and malformed artifacts; test
  collisions, untrusted cache fallback, source-backed rechecking and source-less
  artifact admission as distinct paths. No test should authenticate executable
  bytes merely by validating Core.
- Inject allocation failure and cancellation at every relevant construction,
  proof, validation, planning, cache and publication boundary. Assert no
  partial output or leaked authority and retention of the last good revision.
  A sampled fault run or a historical test count is not full qualification.

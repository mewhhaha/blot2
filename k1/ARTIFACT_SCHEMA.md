# Proposed K1-00 completed-artifact boundary

**Design proposal, not an implemented format or a qualification claim.** This
proposal makes the scalar K1-00 vertical slice reviewable. It is distinct from
`BLK1SC01`, `BLK1SC02`, the v3 module fixture and the v4 add fixture. None of
those formats or in-memory records is a completed K1 artifact. The authority
is [K1-CORE #38](https://github.com/mewhhaha/blot2/issues/38), especially
C01–C06 and C11, [K1-MEM #41](https://github.com/mewhhaha/blot2/issues/41),
and the qualification gates in [K1-EXEC #39](https://github.com/mewhhaha/blot2/issues/39).
The format and choices below require review before implementation.

## Scope and separation of authority

The first artifact schema below admits one monomorphic, noncapturing, private
`U32 -> U32` leaf, with an explicit return of its parameter or a U32 constant.
It has no binders, contracts, effects, calls, captures, regions, ownership,
proofs, static evaluations or helper dependencies. No operation requiring a
proof is represented. Unsupported content must be rejected, not interpreted
as this subset. Later syntax and operation families require explicit schema and
validator extensions; an unknown tag is never a no-op.

Produce three **separate owned immutable objects**: a `CheckedInterface`, a
`CheckedFunction` linked to that exact interface, and a target-specific
`LoweringPlan` linked to that exact body. A source map is a separate optional
object. Neither a parser record, v4 fixture proof, machine-code byte string nor
a digest is one of these objects. Completion must establish all semantic and
baseline representation obligations before sealing. Independent validation
reads sealed values, does not use mutable frontend state, and does not infer or
repair omitted information. Lowering cannot reopen inference. A failed check or
optional transform cannot publish a partial replacement for a successful
revision.

The 16 MiB limit is **per complete serialized object**, including header,
directory and data. A decoder must establish it before allocation and enforce
the same limit for a required artifact and an optional cache candidate. Source
has its own 16 MiB limit. These limits do not authorize importing an
unauthenticated work receipt or executable payload.

## Producer identity and trust boundary

A producer is the canonical tuple `(package identity, logical module path,
declaration path)`, not a numeric table index or implementation digest. For
this slice, declaration path is one top-level identifier. A later schema must
specify structural nested-declaration path components. Whitespace and source
byte offsets do not change a top-level declaration identity. A declaration's
body or interface edit changes its semantic digest, not its producer tuple.
Abstract region/domain binders and generative introduction sites must remain
separate identities in later schemas; no runtime nonce is serialized.

The compilation request supplies a package identity established by the package
resolver. **Unresolved design choice:** a canonical package-identity scheme,
its namespace/version and authority rules are not specified here. A decoder
must compare the complete canonical tuple against the request and dependency
records, not accept an artifact's self-asserted name or derive package identity
from an absolute host path. The resolver must define collision and imported
package behavior before cross-package artifacts are usable. A digest can index
candidates; it does not turn an untrusted producer claim into authority.

For this proposal, logical module path is a nonempty slash-separated sequence
of UTF-8 components relative to the admitted package root; empty, `.`, `..`,
backslash, NUL and absolute components are rejected. Resolution, including
symlink containment, happens before forming the identity. An exact case and
Unicode normalization policy must be chosen consistently by the resolver; do
not silently normalize during decoding. Declaration components are exact K1
ASCII identifiers, with reserved names rejected. Cross-artifact references
carry the full producer tuple and refer to a validated owner-local table
projection. The semantic artifact owns the strings: no source slice,
interning ID, pointer or process-local nonce may escape completion.

## Proposed envelope v1

All integers below are unsigned little-endian. No native struct bytes are
serialized. A `u8str` means a `u32` byte count followed by exactly that many
valid UTF-8 bytes; string length is checked against the remaining object and
its applicable semantic limit before copying. Type and operation tags are
numeric schema identifiers, not source spellings. This proposal reserves zero
as **absent** only in fields explicitly described as optional; owner-local
value IDs here are zero-based, so value ID 0 is the parameter and is not an
absence marker.

The 24-byte fixed header is:

| Offset | Field | Constraint |
| ---: | --- | --- |
| 0 | 8 bytes `K1ART001` | Exact magic; not an SC01/SC02 container |
| 8 | `u16` envelope version | 1 |
| 10 | `u8` kind | 1 interface, 2 function, 3 lowering plan |
| 11 | `u8` flags | 0 in v1 |
| 12 | `u32` total bytes | Exactly the supplied byte length; at most 16 MiB |
| 16 | `u16` section count | Exact count for kind below |
| 18 | `u16` reserved | 0 |
| 20 | `u32` directory bytes | Exactly `section count * 12` |

Each 12-byte directory entry is `u16 section_id`, `u16 flags`, `u32 offset`,
`u32 length`. Flags are zero. Entries are strictly increasing by section ID,
with exactly the required IDs for the kind. Payloads start immediately after
the directory, occur in directory order, are contiguous, and consume the object
exactly. Empty mandatory sections have zero length at the current cursor.
Unknown, missing, duplicate or reordered sections, gaps, overlap, trailing
bytes and nonzero reserved fields are rejected. Check `offset <= total` and
`length <= total - offset` before computing an end; similarly check directory
multiplication/addition before reading. No allocation or `bytes[offset..end]`
is allowed before the fixed header, directory bounds and 16 MiB ceiling pass.
The decoder then validates each section's exact payload length and counts
before accessing a table item.

The deterministic section IDs are 1 versions, 2 producer, 3 interface contract,
4 interface link, 5 function body, 6 target plan, 7 observations, and 8
required-work receipt. Interface requires `[1,2,3,7]`; function requires
`[1,2,4,5,7,8]`; plan requires `[1,2,4,6,7]`. Each v1 section layout below is exact, not a suggestion to
ignore unknown bytes. An origin map and manifest/certificate have separate
schemas and are not embedded as extensions to this envelope.

### Versions and producer sections

Section 1 contains four `u8str` values in order: edition `k1`, semantic policy
`K1-SEM-POLICY-1`, optimization policy `K1-OPT-POLICY-1`, target ABI
`K1-WASM32-ABI1`; then 32 bytes of ABI hash. Compare each against the request
and selected implementation before following semantic links. Section 2 is
package identity `u8str`, logical module path `u8str`, `u32` declaration
component count (exactly 1 in this subset), and that many `u8str` components.
Both strings and their enclosing directory spans are bounded before use.

The ABI hash is **not** `hash("K1-WASM32-ABI1")`. M10 requires a hash over
canonical versioned primitive schemas, layouts, owner fields and encodings,
dictionary and call conventions, limits, and host wire schema. The exact
canonical ABI descriptor bytes and hash domain remain an open choice coordinated
with the memory/manifest design. Until that is specified and implemented,
this proposal cannot produce a qualified ABI hash or a K1-00 artifact. Interface,
function, plan, manifest and structural certificate must bind the same
computed ABI hash; the per-module geometry has its own manifest hash.

### Interface contract section

Section 3 is the following exact sequence of `u32` words:

`parameter_type, result_type, parameter_count, call_mode, effect_bits,
binder_count, capture_count, precondition_count, postcondition_count,
dictionary_count, layout_premise_count, data_identity_count, depth, frame_bytes`.

For the initial slice, types are U32=1; both type words are 1,
`parameter_count=1`, Many=1, all effect/count fields are 0, `depth=1`, and
`frame_bytes=0`. These zeros state *closed absence*, not unspecified information.
The subset has no data identity or visibility payload beyond its producer;
acceptance cannot be generalized to declarations that do. A later schema must
encode all C05 binders, contracts, effects, dictionary signatures, premises,
nominal identities and visibility explicitly instead of treating new content
as zero. Interface semantic equality excludes source-origin positions and
physical backend local choices. ABI realization has its own dependency.

### Function link and body sections

Section 4 for a function contains a length-delimited full canonical interface
producer tuple (same encoding as section 2) and its 32-byte interface semantic
digest. Require the tuple to equal section 2's producer and the resolved
interface's full tuple; independently validate the referenced interface and
compare its canonical semantic bytes as well as its digest. A supplied digest
alone is never a link proof. A plan's section 4 extends that link with the
32-byte function semantic digest, likewise resolved and structurally checked.

Section 5 begins `u32 block_count=1`, `u32 value_count`, `u32 operation_count`,
then `value_count` records in implicit owner-local order. Each value record is
four `u32` words: `producer, type, operation, bits`. Value 0 is exactly
`(parameter=1, U32=1, 0, 0)`. The parameter-return body has one value and zero
operations. The constant-return body has a second value
`(constant=2, U32=1, 0, literal_bits)` and one operation. No second parameter,
unknown type, operation, value or dead value is admitted. Finish the section
with `u32 terminator=1` (explicit return), `u32 result_id`, then six zero `u32`
counts for calls, captures, ownership transitions, evidence, static results and
semantic substitutions. Result ID is 0 for parameter return or 1 for constant
return. A validator checks the result value exists, has U32 type, dominates the
terminator and is the sole returned value. The constant's bits are arbitrary
U32; they are not signed semantic conversion.

This compact leaf schema is not the complete C03 grammar. In a larger schema,
blocks/joins, explicit operands, edges, substitutions, effect/usage transitions,
proof DAGs and all C05 tables need explicit IDs, scopes and bounds. A zero proof
operand cannot establish evidence. All earlier dependencies and obligations
must be present and validated; no late overload selection is permitted.

### Plan section

Section 4 carries the checked function link. Section 6 contains exact `u32` words:
`abi_kind, environment_kind, parameter_kind, result_kind, result_slot_kind,
adapter_count, representation_substitution_count, helper_count,
backing_allocation_count, depth, frame_bytes, code_policy`.
For this leaf, `abi_kind=1` is the canonical K1 convention; environment,
parameter and result kinds are i32=1, result slot is absent=0, all counts are
0, depth is 1, frame bytes 0, and `code_policy=1` is the documented baseline
encoder. The call is `(environment:i32, argument:i32)->i32` and its environment
is zero for this noncapturing leaf. The plan must match the checked signature
and body and cannot switch a type, introduce hidden allocation, alter nominal
identity, or make a general inference request. No executable byte array is a
plan field. The physical memory geometry belongs to the validated manifest;
section 6 must bind its canonical identity/hash in the final schema once that
schema is agreed, rather than duplicate unreviewed magic offsets here.

### Required-work receipt section

Section 8 contains nine `u32` words: `semantic_visits, proof_visits,
proof_terms, proof_edges, core_operations, core_blocks, static_steps,
static_depth, static_bytes`. Each must be at most its corresponding C09 limit;
counts inconsistent with the represented body are invalid. In this leaf,
`core_blocks=1`; `core_operations=1` for parameter return and 2 for constant
return, including the terminator. Proof and static fields are zero. This small summary
is a proposed minimum framing, not the complete ordered phase/event receipt:
[WORK_SCHEMA.md](WORK_SCHEMA.md) identifies the required policy, attribution,
phase trace and remaining design choices. The current proposal does not define
how to encode every ordered phase/event and dependency observation yet. Until
that schema is frozen, these words cannot establish a complete C05 receipt.
An untrusted stored summary is never used as proof that required work occurred;
source-backed admission redoes required work. Only a trusted in-process seal
may bind an actual immutable receipt to the exact completed object and policy.

### Observations section

Section 7 begins with `u32 count`; it is 0 for this closed leaf only if the
completion actually observed no external fact. A future nonzero entry has an
explicit dependency category (interface, implementation, required static
value, ABI/layout, capture graph, operation/provider, source origin, or negative
lookup), producer tuple or explicit lookup key, and canonical observed value.
The completed format must record observations in deterministic order and sort
external-reference tables by their full canonical identity. Ordered semantic
reads and negative lookups cannot be omitted merely because current fixture
code has no imports. Interface semantic comparisons, body/static and ABI
consumers are separate: an unchanged interface may cut off a caller's semantic
recheck only when all observations actually used remain equal.

## Hashes, origins and admission

Use the repository's BLAKE3 infrastructure with distinct, versioned hash domains
for interface semantic bytes, function semantic bytes, ABI descriptor,
per-module manifest and origins. The reviewed proposal in
[MANIFEST_SCHEMA.md](MANIFEST_SCHEMA.md) uses `blot-k1-abi-profile-v1\0` and
`blot-k1-manifest-v1\0`, each followed by a little-endian `u32` byte length
and its exact canonical bytes. Full ABI profile bytes are not yet frozen.
Interface/function/origin domains and exact digest inclusion rules remain open;
the digest must not include its own field. An interface semantic-digest
projection includes the producer, edition, semantic policy and completed
semantic interface/observations, while excluding origins, optimization policy,
ABI realization and backend-local choices; its envelope and artifact keys still
carry all required policy and ABI versions. Function semantic digest includes
the exact interface semantic link and body/evidence. ABI and manifest hashes
are separate. The exact projection encoding and independent test vectors must
be reviewed before implementation. A digest mismatch rejects a link, but a digest
match never replaces full bounded decoding, exact producer comparison, semantic
validation or trusted provenance. No hash value authenticates a producer.

An optional source-origin object is separately keyed by exact source identity
and owns bounded mappings from admitted semantic nodes to source byte spans.
A changed whitespace/origin map need not change semantic identity. The choice
of source-identity encoding and source-map schema is open; do not use a source
path or an asserted digest as authority for semantic validity. Source-backed
admission independently binds the input source, package configuration and the
completed artifact. Exact source bytes, not merely their digest, must be
available for any required source recheck.

Do not serialize a process capability or trust a `validated`, `proved`,
`already charged`, `same job` flag, arbitrary receipt, or mutable session
counter. An in-memory receipt is authority only if sealed by the trusted current
completion process and bound to the exact artifact and policy. The current v4
fixture's owner/scope `1` and by-value Work counters cannot authenticate a
cross-compile proof; this format must not encode them as authority.

## Validation and publication order

1. Check supplied byte length, magic, edition/version/policy and directory
   geometry before any data-dependent allocation, slice or table lookup.
   Distinguish incompatible version/ABI from malformed supported version.
2. Decode into private temporary owned storage with bounded exact counts; reject
   unsupported content. Validate UTF-8 and canonical encodings, table indexes,
   names and identity against the selected package resolver. The subset's table
   size is 1 block and at most 2 values; future table limits also include C09's
   4,096 blocks, 65,536 operations and finite work limits. Check sizes and
   charges before growing a table.
3. Validate the complete interface, exact body link, operation/operand schemas,
   dominance, explicit return, effects, resource and representation feasibility
   independently. Check all declarations, including unused closed-invalid ones.
   For future evidence check exact operands, scope, derivation and prerequisite
   ordering, initialization and ownership—not a Boolean proof flag.
4. Check the plan against the validated function and reviewed ABI/geometry;
   verify all adapters, roles and transitive helper dependencies. Reject a
   legacy managed helper or mismatched call signature. No unrecorded operation,
   incomplete contract, hidden semantic inference or optimizer-dependent
   admission is allowed.
5. Select executable provenance explicitly. For untrusted attached executable
   bytes, ignore them and regenerate from the validated plan. A structural Core
   certificate does not authenticate arbitrary Wasm. Only separately trusted
   build provenance tied to the exact bytes may authorize reuse; no new
   signature scheme is assumed.
6. Publish the new completed semantic revision atomically only after required
   validation and admitted work finish. OOM, interruption, a malformed input or
   failed optional rewrite cannot replace the last good revision.

An optional malformed/stale cache entry is discarded and rebuilt from source.
A required source-less import gets `k1_invalid_artifact` or
`k1_incompatible_artifact`; validate it under the explicit artifact policy and
do not claim fresh-source parity. A compiler-generated invalid fresh object is
an internal compiler error and is never published. For a source-backed candidate
without trusted in-process provenance, recompute required source admission with
the same semantic policy before promotion. Hashes and untrusted receipts cannot
make a warm cache accept a source that fresh checking would reject or exhaust.

## Review and qualification gates

- Golden deterministic bytes and cross-process re-encoding for each artifact;
  parameter and both U32 boundary constants; separately keyed origin changes.
- Truncation at every byte; oversized total, invalid directory arithmetic,
  offsets, lengths, overlap, trailing data, invalid UTF-8, unknown version/tag,
  duplicate/reordered sections, invalid reserved bits and noncanonical tables.
- Wrong package/module/declaration producer, forged digest, changed source,
  stale interface, omitted/negative dependencies, ABI/manifest mismatch,
  malformed result ID, type, effect/resource, terminator or operation.
- Deliberate same-hash candidate substitution in a test hash adapter must not
  bypass exact semantic/dependency comparison. Forge a cheap work receipt for
  source that exceeds a fresh limit and ensure fresh admission still fails.
- Attach changed executable bytes to an otherwise valid Core: discard and
  regenerate them unless an independently trusted exact-build provenance path
  is explicitly implemented and tested. Validate emitted helper roles and fixed
  memory geometry separately from the semantic artifact.
- Fault injection at each allocation/publication step, cache miss/hit and
  source-less import outcomes, cold/warm and worker-schedule parity, and a
  demonstrated ban on downstream solver creation. A passing structural test is
  not a mathematical proof of the compiler or runtime.

Open decisions before implementation: package identity and resolver authority;
canonical Unicode/case rules; full ABI descriptor and hash bytes; manifest and
structural-certificate formats; hash domain strings; origin/source-map schema;
nonzero dependency/negative-lookup encoding; complete ordered work-receipt
encoding; and trusted current-process seal
and transactional storage. The first implementation must document these choices
and run the stated gates rather than assigning provisional values and calling
the result K1-00 complete.

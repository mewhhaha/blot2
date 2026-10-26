# K1 ABI profile: proposed canonical schema for review

Status: **design draft, not an implemented or supported ABI profile**. No byte
sequence in this document is the `K1-WASM32-ABI1` profile or its digest. The
normative requirements remain [K1-MEM #41](https://github.com/mewhhaha/blot2/issues/41),
[K1-LANG #40](https://github.com/mewhhaha/blot2/issues/40), and
[K1-CORE #38](https://github.com/mewhhaha/blot2/issues/38). In particular,
M10 requires the ABI hash to cover *all* versioned primitive schemas, layouts,
owner fields and states, dictionaries, call conventions, limits and host wire
schema. A scalar-only profile, fixture JSON, label string or hash of Markdown
is insufficient. The supported hash remains blocked until the implementation
choices and complete machine-readable tables below are frozen, independently
encoded and decoded, and bound consistently through checked interfaces,
functions, manifests and certificates.

## Normative boundary and implementation choices

The specification defines the logical and physical rules, but not a concrete
byte serialization for this profile. The following are **proposed local format
choices**, not facts prescribed by M02–M12:

- Profile magic `K1ABIP01`, serialization version 1, U32 little-endian fields,
  bounded length-prefixed records, stable record identifiers and ordering below.
- Choose `#False = 0`, `#True = 1`, and `Result` declares `#Ok = 0`, `#Err = 1`.
  LANG §4 defines `Option` in the order `#None | #Some(T)`, so the M02
  declaration-order rule yields `#None = 0`, `#Some = 1`. Preserve M04's order
  `ReserveError = [SizeOverflow, NoOwnerSlots, NoContiguousSpace]` and
  `AllocError = [SizeOverflow, NoSpace]`, giving tags 0, 1, 2 and 0, 1.
  These choices do not make Result Share or remove its must-handle duty.
- Numeric IDs below identify entries **within this profile version**, not
  types in arbitrary artifacts. Per-module schema IDs remain local projections
  of complete canonical schema bytes. Equal numbers from distinct producers do
  not establish equality. Table-code zero is reserved for invalid handles by
  this proposed implementation; code `n>0` maps to Wasm table index `n-1`, so
  valid Wasm table index zero is not discarded. A checked callable always names
  a validated immutable entry, not a fabricated source integer; checked
  conversion precedes any indirect call.
- The first control-schema proposal is an explicitly versioned four-word
  control region: `busy`, `poisoned`, `frame_top`, and `reserved`, all U32 in
  that order, initially zero. The reserved word stays zero. Region offsets are
  per-module manifest data, not ABI-profile constants. This choice needs a
  concrete wrapper/runtime validator and must not be treated as M03 requiring
  that particular control layout. An engine trap cannot be relied upon to write
  the Wasm `poisoned` word: the host wrapper separately records a poisoned
  instance and never resumes it. The word is at most a checked runtime mirror.
- Scalar-only host exposure is **not defined here**. M10's canonical internal
  `(environment, source-argument)` callable and an optional
  declaration-fixed thin entry are specified below; an exported test-only thin
  entry does not establish a public scalar host protocol. The precise public
  scalar wrapper, engine/poison contract and resource preflight must be frozen
  and tested before an export record can claim that support. The array bridge
  has the separate required M12 protocol below.
- To avoid silently changing accepted input, the canonical-wire rule for
  unreferenced input gaps is unresolved: M12 requires zero padding and allows
  overlapping read-only input ranges, but does not explicitly identify every
  unused payload byte as padding. Do not treat the present stricter scalar
  planner's gap check as a normative rule until independently reviewed.

## Canonical framing

The proposed profile is bounded to 16 MiB including framing and contains no
host pointer, solver handle, platform `usize`, native padding or hash-table
iteration order. All U32 integers are four-byte little-endian. A boolean field
is U32 exactly 0 or 1. A byte string is `u32 byte_length` followed by exactly
that many bytes. Identifier and text fields, where explicitly allowed, are
UTF-8; registry identifiers below are restricted to ASCII and contain no NUL.
A vector is `u32 count` followed by exactly `count` complete elements. Decoder
checks each length/count by subtraction against the containing frame and the
fixed table budgets before slicing, allocating or following references.

```text
profile := magic[8] = "K1ABIP01", u32 format = 1, u32 record_count,
           record[record_count]
record  := u32 section, u32 id, u32 record_version = 1,
           u32 payload_bytes, byte[payload_bytes]
```

Records are strictly ordered by `(section,id)`, duplicate or unknown pairs,
unknown versions, nonzero reserved fields, trailing bytes and noncanonical
nested representations reject. A required section and every required record
must appear exactly once, even if the current compiler does not yet admit that
operation. Schema/operator support is a separate supported-feature table and
cannot be inferred merely because an ABI record exists. A digest cannot fill
missing records or license unsafe decoding.

Proposed section tags: 1 scalar and layout rules; 2 built-in descriptors and
sum tags; 3 fixed resources and owner state; 4 dictionary and call ABI;
5 primitive schema/behavior registry; 6 host wire and lifecycle; 7 cross-cutting
failure, initialization and ownership rules. Per-module addresses, actual
memory size, concrete layouts, callable contracts, exports and pool/window
configuration are **not** substituted into these template records: those are
bound by the separately encoded manifest and its manifest hash.

Nested type templates use explicit kind tags and parameter/binder indexes;
those indexes are unsigned, checked before dereference, and local to the
record. Each variable-length child or field sequence is count-prefixed and
kept in semantic source order. Unordered external reference tables are sorted
by complete canonical producer identity and complete schema bytes, with
lexicographic byte ordering, and duplicate entries reject. Versioned rule
identifiers name a fixed local semantic definition; a familiar source spelling
alone does not authorize an operation. Concrete type schemas must serialize the
full ordered structure and guards—not only a template ID, a size, a dictionary
flag or a digest. How that concrete schema byte grammar is represented in the
artifact is still a freeze prerequisite and must not be silently guessed from
these templates.

Hash input, as proposed in `MANIFEST_SCHEMA.md`, is exactly:

```text
BLAKE3-256(ASCII("blot-k1-abi-profile-v1") || 0x00 ||
           u32le(profile_byte_length) || profile_bytes)
```

The profile never includes its own hash. The compiler independently compares
canonical supported profile bytes and recomputes BLAKE3 before claiming
compatibility. An ABI digest is only a compatibility/fingerprint value; matching
it cannot authorize source, producer, type identity, Core, external machine
code or a forged certificate. No supported digest or golden vector is asserted
until the payload encodings and complete registry are reviewed and frozen.

## Section 1: scalar and layout rules

Required records (IDs are local proposed IDs, version 1):

| ID | Template | Canonical rule which its payload must encode |
| --- | --- | --- |
| 1 | machine | Wasm32, little-endian, 4-byte word; nonempty alignment 4; no interior headers |
| 2 | Unit | size 0, alignment 1, no loads/stores; logical count/bounds still apply |
| 3 | U32 | size 4, alignment 4; exact unsigned 32-bit bits |
| 4 | Bool | size 4, alignment 4; only 0/1 valid, mappings stated above |
| 5 | F32 | size 4, alignment 4, IEEE binary32; language NaN/copy/negation rules apply |
| 6 | Index | stored U32 plus erased exact Domain/Nat refinement; no forged constructor |
| 7 | product/record | ordered fields concatenated; explicit complete child schemas and declared order |
| 8 | closed sum | U32 declaration-order tag plus maximum arm payload; inactive words zero; at most 4 arms |
| 9 | builtin Result | same bounded tagged representation but distinct affine must-handle identity, never Plain/Share |
| 10 | existential | ordered stored Nat prefix (one U32 each) followed by payload; Domain binders erased, no Type/Region existential |
| 11 | array element | stride equals exact element size; Unit uses stride 0; no runtime stride word in View |
| 12 | classification | Plain <=64 bytes, <=32 structural nodes, <=64 scalar leaves, <=32 validity guards; ordinary aggregate/environment <=256 bytes; explicit Plain/Share exclusions from M02 |

Concrete profile records need explicit binder counts/kinds, exact layout-rule
IDs, size/alignment calculation and validation guards. Generic bounded layout
computation cannot discover new inference at runtime; a limit or overflow is a
checked rejection, not a guessed shape. Zero-sized slots may use address zero
and perform no memory access; that bit pattern does not duplicate authority.

## Section 2: descriptor and sum schemas

Each named descriptor is a distinct semantic role even when the physical
record has equal words. All words below are U32 in declaration order.

| ID | Role | Fields |
| --- | --- | --- |
| 1 | View | `data, length` |
| 2 | Dest | `data, capacity_elements` |
| 3 | EnvDest | `data, capacity_bytes` |
| 4 | Builder | `data, initialized_length, capacity` |
| 5 | RegionOwner | `slot, generation` |
| 6 | Space | `slot, generation` |
| 7 | Owned | `slot, generation` |
| 8 | OwnedConstruction | `slot, generation` |
| 9 | Fn | `table_code, environment` |
| 10 | layout dictionary | `size_bytes, alignment_bytes, flags, schema_id` |

Empty nonzero-sized Views are `{0,0}` and zero-sized element Views are `{0,n}`.
Zero-sized Dest and builder transitions retain their distinct checked affine
state despite a zero address. FnMany and immutable Views are Share with their
loans; FnOnce, Owned and mutable authorities are not. Captures must be Share,
with every loan outliving its environment. No implicit closure box, reference
count, collector, owner graph traversal or runtime partial-move bitmap is added.

The profile must encode the exact tag mapping in the preceding choices, sum
payload geometry and inactive zeroing. Reserve/Alloc failure tags preserve the
ordered variants and priority in M04. Logical failure, runtime invariant fault,
engine trap/poison and optional optimization decline remain different outcomes.

## Section 3: resource and owner profile

Required scalar constants and hard limits include: page 65,536 bytes; backing
granule 4,096 bytes; owner record 32 bytes; root capsule 256 bytes; maximum
linear memory 1 GiB exclusive end `0x40000000`; maximum owner slots 4,096;
maximum frame arena 16 MiB; maximum call depth 128. Defaults are pool 16 MiB,
256 owner slots, frame arena 1 MiB, ingress 64 KiB, egress 64 KiB. A manifest
may select different allowed values, with one fixed memory and equal min/max
pages. Initial pages are the checked ceiling of the selected map's actual end;
all static, dictionary, control, owner, bitmap, frame, ingress, egress, padding
and pool bytes must be represented and disjoint as required by M03. Bitmap is
`ceil(granules/8)` rounded to four bytes; pool starts on a 4,096-byte boundary.

Owner entry word order is exactly `base, requested_bytes, rounded_bytes, top,
generation, state, root_schema, root_words`. Proposed records encode state
values `Free=0, Open=1, SealedOwned=2, Retired=3, BuildingOwned=4`; slot 0 and
generation 0 are invalid handles. Initial slots are Free/gen 0. Reservation
increments the chosen generation without wrap; closing generation U32.MAX
retires it. First reusable slot and first free contiguous granule run are
chosen in ascending order; failure preserves slot and bitmap. Requested bytes,
not rounded slack, are authority. Ordinary zero-byte reserve uses a slot and no
granule; Owned zero-work still reserves its 256-byte root capsule.

An implementation-specific control-schema record must encode the four proposed
control words and initial values above, plus state-transition rules. No code
currently validates this complete control schema. Until that happens an emitted
module cannot claim its actual control bytes are certified merely because a
manifest contains a familiar tag.

## Section 4: dictionaries and callable ABI

The four dictionary words are size, alignment, flags and schema ID; flags are
`Plain=1`, `Share=2`, `ZeroSized=4`, all other bits zero. The dictionary is
compiler-created, immutable and validated with the corresponding generic
binder and canonical type schema. It is not an arbitrary runtime integer cast
or a generic destructor/copy authority.

Canonical machine parameter order is environment pointer; indirect result slot
if needed; layout dictionaries in binder order; explicitly reified Nat
witnesses not already supplied by a designated descriptor field; source
argument representation. Proof evidence and Region and Domain binders have no
runtime tag; this does not erase reified Nat witnesses or the separate physical
RegionOwner/Space handle words. A Unit argument or result contributes no
machine value. Noncapturing environment is zero.
Statically known U32/Bool/Index use i32 and F32 uses f32. Products, sums,
Views, builders, owners and other nonscalars use caller-provided aggregate
slots. Generic `T` stays indirect even for a scalar instantiation. An aggregate
result writes an exclusive slot and returns no scalar. No multivalue is needed.
The checked contract determines borrowed versus affine-moved inputs; physical
indirection does not license copying.

A function descriptor is `{table_code, environment}` with immutable table
contents and a complete compatible callable contract. Many may weaken to Once,
not vice versa; a Once call consumes the callable. A declaration-fixed thin
entry may omit the environment argument, with one checked canonical adapter;
the chosen entry and adapter identities belong to that declaration's completed
ABI, not to arbitrary call sites. This is not a host export by itself.

Every callable carries finite `{depth, frame}`. Depth is 1..128; a caller
proves `1 + max(callee.depth) <= caller.depth` and
`own_frame + max(callee.frame) <= caller.frame`. The frame is checked
linear-memory storage, restored on every exit, and excludes separately stated
engine/JIT/native stack capacity. Callback-hidden cycles are rejected. No
symbolic resource polymorphism is introduced. Host wrappers preflight before
source effects and must not rely on a Wasm trap as a recoverable frame failure.

## Section 5: primitive registry schema

Every primitive specialization in this profile needs its own stable,
versioned entry (or a canonical fully specified family ID plus a checked exact
specialization). An entry encodes ordered operand/result type expressions,
binder kinds and substitutions, required and generated proof facts, exact
read/write/place/reset regions, failure/divergence/reservation/identity and
cleanup observations, copy/move/borrow transitions, initialized-state changes,
representation feasibility, evaluation order and lowering/helper identity.
No optimizer, source alias, familiar name, supplied numeric tag or digest can
invent a missing field. Runtime helper implementation versions are part of the
checked runtime profile, and helper contracts require their own tests.

The complete M02–M12/C03 family inventory that must be expanded into concrete
records is:

| Family | Required schema distinctions |
| --- | --- |
| scalar/Bool | Each U32/F32/Bool comparison and Boolean operation, exact result and short-circuit order; F32 rounding/NaN rules |
| total U32 bitwise | unary `~`, binary `&`, `^`, `|`, all exact 32-bit operations without arithmetic evidence |
| F32 arithmetic | binary `+`, `-`, `*`, `/` and unary `-`, with separate rounding and no reassociation/FMA; runtime arithmetic NaNs follow the specified allowed set, copies preserve bits, and negation changes only the sign; required-static arithmetic uses positive canonical quiet NaN `0x7fc00000` |
| checked U32 | add, subtract, multiply, divide, remainder and shifts with their exact AddFits/SubFits/MulFits/nonzero/shift-count evidence |
| explicit U32 wrapping/fallible | wrapping add/sub/mul; try add/sub/mul/div/shift-left/shift-right; each failure Result and success fact distinct |
| U32 fits/conversions | fits add/sub/mul Boolean contracts and explicit fallible conversions; no Index minting by cast |
| reservation | `region.reserve` and `owned.begin`, distinct zero-byte/capsule geometry, error priority, identity and release obligations |
| placement | `region.try_alloc`, proved `region.alloc`, `env.try_alloc`; exact consumed/success/failure frontier and size/alignment checks |
| destination | `dest.split`, `dest.discard`, and `space.end`; exact exclusive derivation and disjointness |
| builder | begin append/resize, read, append/try_append, set, truncate, freeze, discard; exact n/c/version/loan and full-element publication |
| view/index | read/try_read, slice, index.try_make, Index.value; exact initialized extent and Domain/Nat identity |
| owner | reset, close, owned seal/abort/open/close; exact state/loan/closedness/capsule and failure cleanup |
| callable | closure capture/environment placement (`fn.place`), Many/Once invocation and checked adapters; no hidden heap or liveness refcount |
| construction | `array.in` and static array initialization, source left-to-right complete-element writes and explicit destination/authority |

The concrete registry must also enumerate Builder reads and initialized-length/
capacity observations as registered nonmoving borrows, along with `owned.open`.
View length observes a copied Share View with its immutable loans preserved; it
does not invoke the affine-borrow exception. Each observation binds to the
exact value/version and applicable loan contract. The `Cap(dest)` ambiguity
is recorded separately in `DEST_CAPACITY_AMENDMENT.md`; no new Dest borrow is
granted here. Short-circuit `&&` and
`||` have control-flow evaluation semantics, not eager binary primitive calls.
Typed Core `constant`, product/variant construction, projection/destructure,
calls/invokes, closure, pack/open/refine and control-flow terminators also need
independently checked schemas; a non-primitive Core node must not be given a
fabricated primitive identity merely to fill this table. The specification
requires explicit fallible numeric/host conversions, but does not enumerate
every host-integer width and conversion spelling in M02–M12. Select only the
fully specified/supported entries, record exact signatures and diagnostics,
and do not invent a broader feature claim while freezing this table.

Further details needing an explicit implementation contract or specification
amendment before claiming a complete registry: LANG section 8 names the
fallible U32 operations and their Result/success facts but does not spell every
error type/constructor/tag or specify `try_rem`; do not add `try_rem` by
analogy. Its finite fact algebra does not explicitly define a serialized
negated-fits fact for each Boolean false path, so preserve the actual false
contract without inventing such an inference rule. F32/host-integer conversion
spellings, host integer widths, rounding/failure categories, and the full
per-type comparison/operator signature matrix also need exact bounded entries.
This is separate from the routine choice of record tags or byte endianness.

**Freeze blocker:** the current compiler registry implements only a few scalar
fixture IDs and does not yet define every concrete entry, generic substitution,
error payload or helper implementation record in this inventory. Therefore this
section is a completeness checklist and schema, not a complete byte table. A
profile built from the present registry MUST NOT be published as the complete
`K1-WASM32-ABI1` fingerprint. Finalize exact byte payloads and independent
validators for each record, including unused operations, before generating a
supported ABI digest. If any operator or builtin family is further expanded by
the language specification, review and version the ABI profile rather than
silently omitting it.

## Section 6: mandatory array host wire

The eight U32 control words are, in order, `abi_tag, export_id, status,
payload_bytes, required_bytes, item_count, detail, reserved`; tag is
`0x4b310001`, reserved is zero and the control header is 32 bytes. An input
View descriptor is `{count,byte_offset}` relative to the start of payload,
never a guest pointer; its range starts after fixed fields/descriptors, is
aligned and wholly in the payload. Immutable input ranges may overlap and are
copied into fresh checked regions; no wire value supplies Domain or Region
authority. Unit arrays carry count but zero data bytes and use a compact host
length representation. The sole result-array descriptor precedes its canonical
contiguous data.

Public bridge entry is `(export_id:i32,input_bytes:i32,output_capacity:i32)
-> i32 status`; `input_bytes` includes its 32-byte header and output capacity
counts payload only. Require `32 <= input_bytes <= ingress_window_bytes`,
ingress `payload_bytes == input_bytes - 32`, matching ABI/export IDs, and
ingress status, required_bytes, detail and reserved all zero. `item_count` is
the manifest-prescribed value or zero. Require
`output_capacity <= egress_window_bytes - 32`. Window bounds, ABI/export ID,
zero control fields, counts,
offsets, arithmetic, Bool/tags, substitutions, required Nat equalities, pairwise
distinct input Domain binders and numeric preconditions are validated before
dependent accesses or source effects. Index/Domain-branded values are forbidden
inside Plain wire payloads transitively; ordinary U32 can be checked afterward.

Statuses are fixed `Ok=0`, `InvalidInput=1`, `OutputTooSmall=2`,
`ReservationFailed=3`, `Busy=4`, `FrameLimit=5`, `LanguageError=6`; Poisoned is
a wrapper state, not a reusable status. Busy does no writes. InvalidInput,
FrameLimit or ReservationFailed can be reported before execution; Busy is
rejected without mutation. OutputTooSmall is determined after execution. Ok and
its payload publish only after complete execution/validation/copy;
`required_bytes` is exact only for Ok or OutputTooSmall and zero otherwise;
`payload_bytes` is the published byte count only for Ok and zero otherwise.
The language error `E` is Unit (detail zero) or a closed nullary sum (detail
is its constructor tag); reservation failure detail is the stable reserve
error tag. Every applicable normal/status exit closes the invocation region if it
was acquired, discharges loans, restores the frame frontier and releases Busy.
An engine trap poisons the instance, which
must not resume. A later retry is a new invocation, not hidden replay.

Eligible array exports are noncapturing Many functions accepting one fixed
record of Plain fields, input Views and exactly one output Dest, returning the
specified `Result[exists[m:Nat,d:Domain] => View[r,U,m,d],E]`. Manifest binds
all type substitutions, limits, exact wire schemas, domains/Nat mapping,
`work_bytes`, frame/depth and error schema. Only effects specified by M12 are
eligible. Actual copy execution, cleanup and a trusted private-memory boundary
are required before support is claimed.

## Section 7: cross-cutting constraints and release gates

Profile rules forbid `memory.grow`, unexpected imports, legacy allocation,
retain/release, tracing/cycle collectors and per-value RC in admitted K1
paths. A structural certificate must independently validate exact typed runtime
roles, all transitive helpers and call targets, access/bounds/initialization and
ownership transitions, resource contracts, ABI hash and selected geometry hash.
A source annotation, digest, or fixture-level counters are not that proof.
Externally attached Wasm is regenerated from admitted Core unless independent
trusted provenance binds exact bytes. Shared semantic/proof/static budgets and
failure atomicity are specified by CORE/EXEC and must be checked in every mode;
profile bytes do not authorize a cached work receipt.

Before calling any generated bytes the supported profile: freeze all concrete
record payload schemas and IDs above; settle the scalar-host and gap choices;
implement deterministic bounded encoder and *independent* decoder/comparator;
verify official and cross-implementation BLAKE3 vectors and mutation, truncation,
unknown-tag, duplicate/order and mismatch laws; bind the same recomputed hash
through interface, function, plan, manifest and certificate; and exercise
actual Wasm plus every relevant runtime-role, fault, bridge and resource law.
The current scalar fixtures, standalone models and proposed records do not meet
those gates and cannot change K1's default or enable public K1 compilation.

## Concrete candidate payload assignments, pending complete profile review

The following defines concrete version-1 payload words for the fixed parts of
this proposed profile. Each bracketed sequence is exactly that sequence of
U32 little-endian words inside the enclosing `record`; there is no implicit
word count or terminator. Record IDs are the IDs in the indicated section.
Reserved values and bit fields not listed are zero. These assignments do not
make the still-missing section 5/7 operation and rule tables complete and do
not authorize publishing a supported ABI digest.

For section 1, payloads are:

| ID | U32 payload | Rule ID meaning |
| --- | --- | --- |
| 1 | `[4, 1, 4, 0]` | word bytes; little-endian tag; nonempty alignment; interior header bytes |
| 2 | `[0, 1, 0, 0]` | Unit size/alignment and zero load/store widths |
| 3 | `[4, 4, 32, 1]` | U32 size/alignment/width and exact-bit validity rule |
| 4 | `[4, 4, 2, 0, 1]` | Bool size/alignment, valid-value count, False then True |
| 5 | `[4, 4, 32, 1]` | F32 size/alignment/width and IEEE binary32 rule |
| 6 | `[4, 4, 1, 1]` | Index stored size/alignment, exact Domain/Nat rule, no raw mint |
| 7 | `[1, 1, 1]` | ordered fields, checked concatenated size, nonempty alignment rule |
| 8 | `[4, 4, 4, 1, 1]` | tag bytes/alignment, maximum variants, declaration-order tags, zero inactive words |
| 9 | `[1, 0, 1, 0, 0]` | Result distinct identity, Ok tag, Err tag, Plain false, Share false; must-handle is additionally required by section 7 |
| 10 | `[4, 1, 0, 0]` | bytes per Nat witness, payload follows prefix, stored Domain bytes, Type/Region existential allowed flag |
| 11 | `[1, 0, 0]` | stride equals element size, Unit stride, View runtime-stride field count |
| 12 | `[64, 32, 64, 32, 256, 256]` | Plain bytes/structural nodes/leaves/guards, aggregate bytes, environment bytes |

Every scalar comparison or arithmetic behavior is separately specified by a
section 5 operation record; the layout record is not evidence of a particular
operation. `1` in rule-position fields means the corresponding version-1 rule
listed in the section above, not an untyped true value that can grant source
authority. A real encoder/decoder must use named definitions and exact payload
widths; if a rule's semantics change, its record version/profile identity must
change.

For section 2, a descriptor payload is `u32 field_count` followed by exactly
that many U32 field-role IDs. Proposed role IDs are: `data=1`, `length=2`,
`capacity_elements=3`, `capacity_bytes=4`, `slot=5`, `generation=6`,
`table_code=7`, `environment=8`, `size_bytes=9`, `alignment_bytes=10`,
`flags=11`, `schema_id=12`. Descriptor record IDs and payloads are exactly:

```text
1 View               [2, 1, 2]
2 Dest               [2, 1, 3]
3 EnvDest            [2, 1, 4]
4 Builder            [3, 1, 2, 3]
5 RegionOwner        [2, 5, 6]
6 Space              [2, 5, 6]
7 Owned              [2, 5, 6]
8 OwnedConstruction  [2, 5, 6]
9 Fn                 [2, 7, 8]
10 layout dictionary [4, 9, 10, 11, 12]
```

Semantic role is the descriptor record ID; identical field payloads are not
interchangeable authority. The Mode, Region, Nat and Domain relationships are
in each complete canonical concrete type schema, not fabricated from these
physical words. Additional sum and helper-result schema records remain blocked
until all section 5 operation payloads are fixed.

For section 3, resource record ID 1 has exactly:

```text
[65536, 4096, 32, 256, 1073741824, 4096, 16777216, 128,
 16777216, 256, 1048576, 65536, 65536]
```

The words respectively mean page bytes, pool granule bytes, owner-entry bytes,
root-capsule bytes, maximum linear-memory end, maximum owner slots, maximum frame
arena bytes, maximum callable depth, default pool bytes, default owner slots,
default frame bytes, default ingress bytes and default egress bytes. These are
profile limits/defaults; a module-specific manifest still supplies selected
values and checked map geometry. Record ID 2 has `[8, 1,2,3,4,5,6,7,8]` for
the eight owner words in the M03 order shown above. Record ID 3 has
`[5, 0,1,2,3,4]` for the exact five owner state encodings. Record ID 4 has
`[4, 1,2,3,4, 0,0,0,0]` for the four *proposed* control fields (busy, poisoned,
frame top, reserved) and their initial zero values. Records ID 5 and 6 are
reserved for the selected bitmap/slot algorithm and overflow/failure transition
rules; their exact payloads cannot be marked complete until the runtime-helper
schema and validation are frozen.

For section 4, record ID 1 is `[4, 1,2,4, 0xfffffff8]`: dictionary word count,
Plain/Share/ZeroSized flag bits and forbidden flag mask. Record ID 2 is
`[5, 1,2,3,4,5]`: canonical parameter-order positions are environment,
optional indirect result, binder-ordered dictionaries, required Nat witnesses,
then source argument; optional positions are omitted only under M10. Record ID
3 is `[1, 0, 1, 0]`: Region/Domain/proof erasure version 1, Unit source machine-word
count 0, noncapturing environment rule 1, and its environment value 0. Record
ID 4 is `[1, 2, 1]`: proposed Many tag 1, Once tag 2, and Many-to-Once
weakening rule version 1. These tags are local schema choices, not physical
permission to duplicate an affine Once. Record ID 5 is `[1,128,1]`: minimum leaf
depth, hard depth cap, and version-1 frame/depth composition rule. Complete
canonical source/ABI type schemas, indirect-slot roles and adapters still need
separate payloads, not derived by treating these numbers as type identities.

For section 6, record ID 1 is `[0x4b310001,32,8, 1,2,3,4,5,6,7,8]`:
wire ABI tag, header bytes, header word count, and field roles `abi_tag`,
`export_id`, `status`, `payload_bytes`, `required_bytes`, `item_count`,
`detail`, `reserved`, in that order. Record ID 2 is `[7, 0,1,2,3,4,5,6]`:
count and fixed M12 statuses in the order Ok, InvalidInput, OutputTooSmall,
ReservationFailed, Busy, FrameLimit, LanguageError. Record ID 3 is
`[2, 1,2]`: input View descriptor count and role IDs `count, byte_offset`.
The remaining M12 checks, error detail rules, validation/publication ordering,
copy-only behavior and cleanup are explicit section-6 lifecycle-rule records;
their numeric payloads must be fixed before a profile is complete. In
particular, these header constants do not settle the scalar-only public host
protocol or gap-padding interpretation.

**Encoding and release gate:** The tables above make fixed scalar, descriptor,
resource and header payloads reviewable. They are not a complete set of
profile bytes. Section 5 still needs the exact finite operation-specialization
payloads (including full signatures, ownership/facts/effects/failure and
lowering/helper versions); sections 3, 4, 6 and 7 still need their complete
behavioral rule payloads. No function may return these partial words as the
supported `K1-WASM32-ABI1` byte stream or its hash. Once the remaining tables
are written, test exact canonical framing and every individual payload,
ordering, lengths, tag/version mutations and BLAKE3 golden values against an
independent encoder before exposing a supported immutable profile identity.

## Candidate primitive-record encoding and unresolved contracts

This subsection specifies a proposed field framing for a version-1 section-5
record. It is deliberately **not a complete record table** and does not permit a
profile/hash to be published yet. It provides an implementable target for the
missing registry, while separating known M04/M06 contracts from details that
need an explicit language/runtime decision. Strings are the bounded,
length-prefixed UTF-8 strings in the common framing; integer and vector rules
above apply. An operation's stable name is ASCII and includes `.v1`.

```text
primitive_payload := string stable_name,
                     vector<Binder> binders,
                     vector<TypeExpr> operands,
                     vector<TypeExpr> results,
                     vector<FactTemplate> requires,
                     vector<FactTemplate> success_facts,
                     vector<FactTemplate> true_facts,
                     vector<FactTemplate> false_facts,
                     u32 observable_flags,
                     vector<RegionEffect> region_effects,
                     vector<Usage> operand_usages,
                     vector<Transition> transitions,
                     u32 failure_rule, TypeExpr failure_payload,
                     u32 evaluation_order_rule,
                     string evaluator_id, u32 evaluator_version,
                     string lowering_or_helper_id, u32 lowering_or_helper_version,
                     u32 target_rule, u32 reserved_zero
```

Each variable-size nested entry is itself `u32 byte_length` plus its exact
payload. No unknown tag, out-of-range binder/operand index, cyclic type DAG,
duplicate un-ordered effect, noncanonical name, unconsumed nested byte or
unknown rule version is accepted. Operand/result vector order is semantic and
is never sorted. Effects whose order is not semantic are sorted by their
complete `(effect_kind, region_binder)` encoding and duplicates reject. A
`Binder` is `{u32 kind, u32 local_index}` with kind Type=1, Region=2, Nat=3,
Domain=4; indexes are contiguous per kind in declaration order. Mode tags are
closed constants, not binders. Numeric tags below are **candidate local
encoding choices**, not values prescribed by the issues.

`TypeExpr` starts with `{u32 tag, u32 payload_bytes}` and exactly one bounded
payload. Candidate tags 1–4 are Unit, Bool, U32, F32 and have zero-byte
payloads; 5 is a Type binder index; 6 is Index with one Domain binder and one
Nat expression; 7 is an ordered product; 8 is an ordered record with field
names and child types; 9 is a declaration-order tagged sum; 10 is builtin
Result with success/error types and distinct must-handle identity; 11–19 are
RegionOwner, Space, Dest, EnvDest, Builder, View, Fn, Owned and Nat/Domain
package respectively. These roles remain distinct even if their words match.
A concrete schema must encode the corresponding kind-correct binders,
capacity/length/mode and payload/call contract in a fixed tag-specific field
order; it must not leave an opaque payload or infer missing information from a
numeric type ID. This document does not yet freeze those nine tag-specific
payloads or a complete canonical concrete-type grammar: their widths, field
orders and recursion/work validation remain a **profile blocker**.

`FactTemplate` needs a tagged, bounded term graph for the exact Eq, Lt, Le,
AddFits, SubFits, MulFits and Index forms of LANG §9, with canonical operand,
component, version, Domain/Region binder and literal references. It must
encode true/false/result branch and scope or prerequisite roles explicitly.
The stable primitive record declares a rule, not a particular proof witness;
the completed checked function carries and independently validates the actual
owner-local evidence DAG. Exact term-expression tags and layout have not been
frozen here, and a Boolean `proved` value or a source-name coincidence is not
an acceptable substitute. RegionEffect must distinguish read, write, place,
reset, reserve, release and host; observable flags must separately distinguish
failure, divergence, reservation, ownership consumption, fresh identity,
cleanup and any additional effect. Usage must distinguish copy with loans,
affine move, the specifically registered temporary borrow, and no use.
Transition records must name exact predecessor/success/failure state and
initialization changes, not just an opcode. Exact numeric enums and complete
per-primitive payloads remain to be independently reviewed before profile bytes
can be considered complete.

The following local stable names are candidate choices, not normative issue
IDs. Existing fixture names `k1.u32.constant.v1`, `k1.u32.bitand.v1`, and
`k1.u32.lt.v1` must not be silently renamed. These names alone are not the
primitive records described above:

```text
k1.{unit,bool,u32,f32}.constant.v1
k1.bool.not.v1
k1.u32.{bitnot,bitand,bitor,bitxor,eq,ne,lt,le,gt,ge}.v1
k1.u32.{add,sub,mul,div,rem,shl,shr}.checked.v1
k1.u32.{add,sub,mul}.wrapping.v1
k1.u32.{add,sub,mul,div,shl,shr}.try.v1
k1.u32.{add,sub,mul}.fits.v1
k1.f32.{eq,ne,lt,le,gt,ge,add,sub,mul,div,neg}.v1
k1.region.{reserve,try_alloc,alloc,reset,close}.v1
k1.env.try_alloc.v1; k1.space.end.v1; k1.dest.{split,discard}.v1
k1.builder.{begin_append,begin_resize,read,append,try_append,set,truncate,freeze,discard,length,capacity}.v1
k1.view.{read,indexed_read,try_read,slice,length}.v1
k1.index.{try_make,value}.v1
k1.owned.{begin,seal,abort,open,close}.v1
k1.fn.{frame,place,invoke_many,invoke_once}.v1
k1.array.in.v1
```

The list explicitly does **not** invent `try_rem`, Bool ordering, aggregate
comparison, unspecified host-conversion widths, a Dest nonmoving-borrow
operation, or eager `&&`/`||` operations. It also does not give a primitive ID
to a non-primitive Core branch, block, pack or projection. Every supported
specialization still needs exact type/fact/usage/transition/failure/effect and
helper payloads and fresh independent validation. IDs may be stabilized only
with matching semantics, rules, evaluator/lowering versions and regression laws.

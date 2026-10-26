# Proposed K1 fixed-memory manifest and structural admission

This document proposes a deterministic implementation format for review. It
is not a specification amendment, a completed manifest implementation, a
structural certificate, or a claim that any current fixture is K1-conforming.
The normative authority is issue #37 and K1-CORE #38, K1-EXEC #39, K1-LANG #40,
and K1-MEM #41. In particular, M03, M10, M11, M12 and M13 apply together.
K1-00 is not complete merely because a scalar Wasm file has fixed memory or a
custom JSON section.

The current `blot.k1.fixture.memory` JSON is descriptive test metadata. It has
no trusted digest, profile identity, complete callable/operation evidence, or
certificate. The private exported function and small pool-guest model are test
instrumentation. Neither is a public K1 host bridge or an admitted K1 module.

## Identity and trust boundaries

There are three different identities:

1. **ABI profile identity.** `K1-WASM32-ABI1` is a version label, not a hash or
   proof. The ABI hash is BLAKE3-256 of a complete, versioned canonical ABI
   profile. That profile must enumerate the versioned primitive schemas and
   behavior, layouts and limits, owner words and state encodings, dictionaries,
   call convention, and host-wire schema required by M10. It must include all
   representation choices needed by consumers, not merely the current scalar
   subset. An implementation must compare against its own supported profile
   bytes and independently verify their digest; externally supplied profile
   bytes or a familiar string do not become trusted authority.
2. **Module geometry identity.** The manifest hash is BLAKE3-256 over the
   canonical manifest body below. The body includes the ABI hash, the complete
   geometry, and module-specific schemas/exports/resources. It is distinct from
   a source digest, semantic interface digest, function-body digest, or an
   artifact's transport checksum.
3. **Executable provenance.** A structural certificate binds the exact ABI
   and manifest hashes and independently admitted typed runtime roles, helper
   graph, callable schemas, and operation/evidence obligations. A matching
   digest or a syntactically correct certificate does not authenticate attached
   Wasm. Externally supplied executable bytes are ignored and regenerated from
   admitted checked Core unless independently trusted build provenance binds the
   exact executable bytes, as required by CORE C11/SEC-05. No new signature
   system is implied.

A profile, interface, checked function, lowering plan, manifest, and structural
certificate must agree on the edition and applicable policy/ABI identities;
each interface, implementation artifact, manifest and certificate carries the
same ABI hash (M10). The certificate additionally binds this exact module's
manifest hash. An ABI/policy mismatch fails before linking, body lowering, or
execution. Local numeric type/schema/function IDs are owner-relative handles;
consumers must resolve and compare complete canonical schema bytes and producer
identity. Equal numbers or digest prefixes do not identify types across owners.

BLAKE3 is an integrity fingerprint, not authentication, authority, proof of
well-typedness, or permission to skip decoding. An attacker who replaces both
content and digest has not acquired authority. Hash lookup may select a
candidate; exact canonical contents, valid producer provenance, structural and
semantic checks establish admission. The logical-work receipt for source-backed
untrusted bytes is never trusted to bypass fresh required checking.

## Proposed canonical envelope

The following is a proposed *local format*, not a normative requirement that
all compliant K1 implementations use these bytes. Integer fields are U32
little-endian; lengths count bytes; strings are length-prefixed UTF-8 (U32
length, then exactly that many bytes); digests are exactly 32 bytes. Empty
strings are legal only where the specific table permits them. All tags are
explicit. There are no host pointers, native `usize`, solver identities,
implicit padding, unordered map iteration, or allocator addresses in serialized
bytes. All reserved fields/bits are zero. A body or individual owned artifact
must not exceed the 16 MiB serialized-object limit of CORE C09.

The proposed envelope is:

```text
8 bytes     magic = ASCII "K1MF0001"
u32         body_bytes                    # size of the entire body below
byte[]      body                          # exactly body_bytes, bounded first
32 bytes    claimed_manifest_hash         # not included in body_bytes/hash input
```

The body has this exact field order:

```text
u32         manifest_format = 1
string      edition = "k1"
string      semantic_policy = "K1-SEM-POLICY-1"
string      optimization_policy = "K1-OPT-POLICY-1"
string      abi_label = "K1-WASM32-ABI1"
32 bytes    abi_hash
string      package_identity
string      logical_module_path
u32         page_bytes = 65536
u32         initial_pages
u32         maximum_pages
u32         owner_slots
u32         owner_entry_bytes = 32
u32         granule_bytes = 4096
u32         root_capsule_bytes = 256
u32         control_schema_id
u32         region_count = 9
Region[9]   fixed_regions                 # ascending region tag
u32         padding_count
Region[]    padding_regions               # ascending address
u32         type_schema_count
Schema[]    type_schemas                  # canonical order; see below
u32         callable_count
Callable[]  callables                     # canonical declaration identity order
u32         export_count
Export[]    exports                       # ascending unique export ID
```

`Region = {u32 tag, u32 start, u32 byte_length}`. The region tags are:
1 static data; 2 immutable dictionaries; 3 control words; 4 owner table;
5 pool bitmap; 6 frame arena; 7 host ingress; 8 host egress; 9 backing pool.
A padding record uses tag 0. Empty regions remain present as `{tag,0,0}`;
they do not cover bytes or create an address. Nonempty regions and padding
must form an exact, disjoint partition of `[0, initial_pages * 65536)`, with
zero-length padding forbidden. Adjacent padding records are merged. This
format's grouping, canonical zero-length encoding, and minimal-page rule
below are implementation choices; they
must not be mistaken for a theorem that the normative spec mandates one
particular ordering of regions. An emitter using another valid map must
normalize it into these region groups or use a separately versioned format.

For tables, `Schema = {u32 byte_length, byte[] canonical_schema}`. Entries are
sorted lexicographically by their complete bytes and duplicates are forbidden;
local schema ID `i+1` denotes entry `i`, and zero denotes absent only in fields
that explicitly allow it. `canonical_schema` must itself be an independently
specified, bounded, versioned encoding of a complete physical type and
validity schema, including scalar kinds, ordered product fields, sum tags and
inactive words, refinements, package Nat prefixes, and generic binder
relationships. This document does not yet define or approve that separate
encoding, so accepting a complete untrusted schema table remains **blocked**.
A numeric schema ID or dictionary flag alone is never evidence of Plain, Share,
closedness, provenance, or ownership.

A `Callable` is framed as `{u32 payload_bytes, byte[payload_bytes] payload}`
and sorted by declaration identity. Its required payload fields are producer
identity (package, logical module,
declaration path), exact complete-interface digest and body/operation identity,
call mode and region/capture/loan contract, canonical ABI signature and any
fixed thin entry/adapter identity, complete effects, depth/frame bounds, and
exact layout/schema, static, helper, and executable dependencies. Each embedded
vector is explicitly tagged/count-prefixed, with canonical order where order is
not semantic. The detailed callable encoding must be frozen with the checked
interface/function schemas before it can be admitted. In particular, hash or
name equality alone cannot supply an incomplete interface or choose an indirect
call target. For K1-00's private scalar fixture the function signature is
`(environment:i32, argument:i32)->i32`, empty effects and captures, depth 1,
frame 0; a test-only export of a private declaration is not a source `pub`
export and cannot be used to claim host-bridge completion.

An `Export` uses the same `{u32 payload_bytes, byte[payload_bytes] payload}`
framing, sorted by unique export ID. Its required payload fields are that ID,
exact completed callable identity and interface digest, explicit type/binder
substitution, ordered source fields and their wire schemas, output destination
schema/capacity, input View max counts, required item-count rule, preconditions,
`work_bytes`, frame/depth bounds, and supported error schema. Array bridges
must include the complete M12 binder/domain mapping and Plain wire-eligibility
checks. A scalar-only first stage may emit an empty public-export table and
exercise its internal function through a separate test fixture. It must not
advertise M12 array support until copying, validation and lifecycle qualify.
The detailed export encoding is also not yet frozen.

### Hash computation and non-circularity

Proposed domain-separated hash inputs, where the quoted ASCII prefix includes
the final NUL byte:

```text
abi_hash      = BLAKE3-256("blot-k1-abi-profile-v1\0" ||
                           u32le(abi_profile_byte_length) || abi_profile_bytes)
manifest_hash = BLAKE3-256("blot-k1-manifest-v1\0" ||
                           u32le(body_bytes) || body)
```

The trailing claimed manifest hash is outside `body` and is recomputed. A
certificate stores the recomputed manifest hash; the manifest body never
contains its own hash or a certificate hash. The body contains `abi_hash`, so a
geometry digest is tied to that ABI without a hash cycle. Any profile/schema
semantics or encoding change requires a version/identity change, matching
updated cross-artifact fixtures and laws. A digest is exactly 32 output bytes,
not a platform integer or truncated hash.

**Unresolved freeze prerequisite:** the *complete canonical ABI profile bytes*
(and the separate schema/callable/export encodings) have not yet been specified
or implemented. Consequently there is no valid ABI hash constant or known
answer vector for this proposal today. Do not hash the markdown text, the ABI
label, a partial table, or the current fixture JSON and call it `K1-WASM32-ABI1`.
Define the full profile records with explicit tags and semantic versions,
review them against every M02–M12 ABI requirement, generate independent
BLAKE3 known-answer vectors, and only then publish a supported profile digest.

## Independent geometry validation

The consumer starts with bounded immutable bytes, not an emitter-owned pointer
or trusted struct. Before following an offset, copying a table or allocating a
variable-sized buffer, check envelope length and every count/length using
subtraction or checked arithmetic. Reject truncation, trailing bytes, unknown
magic/version/tag, noncanonical ordering, duplicate IDs, unknown flags,
invalid UTF-8 and invalid required zero fields. Apply 16 MiB object bounds,
8,192 frozen type nodes, nesting 64 and the shared semantic-work policy;
charge repeated table/edge/overlap walks, including helpers. Input-specific
per-table limits must belong to a versioned supported policy, not silently
change K1 acceptance or increase budgets for a hard case.

Use checked wide or subtraction-based arithmetic, but prove every value fits
U32 and the Wasm32 bounds before serializing or narrowing:

1. Require `initial_pages == maximum_pages`, a positive page count, exact page
   size 65,536 and `initial_pages * 65536 <= 0x40000000` (1 GiB). A module has
   one defined memory, with these exact min/max values, and no memory import or
   `memory.grow`. The complete Wasm representation is checked separately.
2. For each region/padding record, check `start <= memory_end` and
   `length <= memory_end - start` before calculating its end. Enforce canonical
   zero-length and sorted/nonoverlap rules; the nonempty records partition the
   entire memory with no missing or doubly claimed byte. Padding is explicit,
   not an invisible overflow gap. Check that static/dictionary/control/owners/
   bitmap/frame/windows/pool occupy their own roles even when physical machine
   values are all i32. Language authority cannot mutate static descriptors.
3. Owner slots are at most 4,096, and `owner_table.byte_length == owner_slots *
   32`; its base is four-byte aligned. The owner record has fields `base,
   requested_bytes, rounded_bytes, top, generation, state, root_schema,
   root_words` in this order, each four bytes. State tags are Free=0, Open=1,
   SealedOwned=2, Retired=3, BuildingOwned=4. Initial owner entries are Free
   with generation zero. A manifest describing geometry does not itself prove
   correct initial bytes or transitions.
4. Pool length is an exact multiple of 4,096, and a nonempty pool start is
   4,096-aligned. Let `granules = pool_length / 4096`; compute bitmap raw bytes
   as `granules / 8 + (granules % 8 != 0)`, then checked-round up to four.
   Require the bitmap region to have exactly that many bytes and a four-byte
   aligned start. Bit allocation cannot overlap other regions. Validate unused
   tail bits and initial zero bitmap according to the fixed runtime profile;
   do not infer ownership from a bit alone.
5. Require a four-byte aligned frame region of at most 16 MiB. Both host
   windows are four-byte aligned, disjoint, and at least 32 bytes including the
   fixed control header. Check every listed static-data, dictionary and control
   subrecord against its declared parent span and schema; the control schema
   must cover Busy, frame and pool runtime metadata actually used by the
   implementation. No arbitrary minimum control-block size is invented here.
6. Compute the highest end of all non-padding regions; round it up to pages
   with checked addition or division and require that count to equal
   `initial_pages`. Every byte thereafter is explicit page padding. This
   proposed profile chooses the smallest page count containing non-padding
   regions; that normalization is stricter than treating an intentional extra
   reserved padding interval as part of the final memory map in M03. Do not
   reject another otherwise valid K1 representation solely on this local rule
   unless it has selected this profile. Validate the actual Wasm memory section and static
   segments against these numbers, rather than trusting manifest strings.

For the current *fixture-only* map, 256 owner entries occupy 8,192 bytes;
16 MiB / 4,096 gives 4,096 granules and a 512-byte bitmap. Its 1 MiB frame and
two 64 KiB windows, 16-byte experimental control range, and alignment give
pool start 1,191,936 and pool end 17,969,152. The fixed memory is 275 pages,
18,022,400 bytes, with 53,248 trailing page-padding bytes. These arithmetic
facts do not supply the missing canonical control schema, ABI profile/hash,
public export contract or proof of any operation's safety.

## Structural certificate and executable checks

A future certificate owns (not borrows) the edition/policy/ABI and manifest
identities; canonical operation IDs and semantic versions; memory/import map;
complete callable signatures and resource bounds; typed runtime roles; the
proof-erasure boundary; exact registered direct/indirect targets and helper
identities; and every backing reservation, placement, reset, close, storage,
initialization, and cleanup action it licenses. Its checked table references
are owner-relative and bounded; origin and dependency observations are tracked
separately from semantic identity. A fresh invalid certificate is an internal
compiler error, never a cache miss. A bad optional cache entry is discarded and
recomputed; a bad required source-less artifact reports `k1_invalid_artifact`
or `k1_incompatible_artifact` as appropriate.

Independent validation must establish, against admitted interfaces/functions
and checked proofs, each typed memory access's layout, initialized extent,
bounds and provenance; exact affine transitions and cleanup on all exits; loan
and lifetime exclusion; frame/depth composition including adapters; and
transitive helper-role contracts. Recheck every dictionary against its
complete schema/binder, not only flags. Validate complete module imports,
exports, table entries and actual fixed memory; reject `memory.grow`, legacy
allocation, retain/release/collector/root helpers, externref ownership,
foreign ABI calls and unregistered indirect targets. The scalar fixture's lack
of imports or a byte scan for `memory.grow` is useful evidence, not this
certificate or a provenance proof. A source annotation such as `kernel` is not
proof of no backing allocation.

Numeric geometry cannot establish that two dynamic domains are equal or
unequal, that a pointer names a live region, or that an owner/loan was moved
correctly. Typed checking and independent Core validation establish those
facts; runtime slots only check generation/state for already-admitted
operations. Host mutation of private memory while Busy and forged metadata are
outside the safe-language guarantee; the public wrapper must keep raw memory
private and poison an instance after an engine trap.

## Required tests before accepting this proposal

- Independently generated canonical-byte and BLAKE3 known-answer vectors;
  same semantic graph with different map/insertion order produces identical
  bytes; altered schema, profile, module geometry or policy changes the
  relevant digest. The exact full-profile vector is pending profile freeze.
- Every envelope/header truncation, oversized count/length, offset addition,
  malformed UTF-8, unknown tag, duplicate and unsorted record, nonzero
  reserved field, unknown schema and forged hash is rejected before access or
  unbounded allocation. Mismatched ABI/edition/policy fails before lowering.
- Geometry at zero, one granule, default and maximum slot/frame values, exact
  1 GiB, one byte/page over, four-byte and 4,096-byte boundaries, bitmap sizes
  around 8/32-granule boundaries, zero slots/zero-sized regions, gaps,
  overlaps, unaccounted page padding and arithmetic overflow. Do not allocate
  huge arrays to test arithmetic planners.
- Actual Wasm instantiation and export behavior for admitted scalar and later
  bounded storage workloads; mismatch between actual memory min/max, memory
  imports, data segments, helper graph and manifest must reject. Include a
  deliberately changed executable attached to otherwise valid metadata: it
  is rebuilt or rejected, never authenticated by metadata alone.
- Deterministic corrupt owner, stale generation, mismatched dictionary,
  cross-owner forged span, forged proof/domain, indirect target, forbidden
  helper, memory.grow, live-loan cleanup, partial initialization, frame and
  host-wire failures. No state or previous successful revision is published on
  an error. Artifact-validation and copy-only-bridge fault sweeps remain
  required; this document and standalone arithmetic tests are not those laws.

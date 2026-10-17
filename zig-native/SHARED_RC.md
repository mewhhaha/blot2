# Typed RC transition

Task 031 adds checked field ownership and iterative destruction while retaining
the tracer. [The ownership design](SHARED_OWNERSHIP.md) remains the
specification for persistent roots, suspension and complete cycle collection in
032–035.

The synchronous root extension is documented in
[Persistent roots](PERSISTENT_ROOTS.md). The qualification below records the 031
boundary and remains the baseline for its additional costs.

## Representation and operations

The nonmoving Wasm32 header occupies 32 bytes. It contains physical/requested
sizes, flags, one phase-exclusive free/mark/destruction link, a strong count, an
exact reference bitmap and two reserved cycle fields. Bit 31 describes every
word from 31 onward; heterogeneous tails decline admission. Allocation classes
include the header. Power-of-two classes start at 64 bytes; below 2 KiB each
also has a 1.5x companion, giving 48, 64, 96, 128, 192, …, 1,536 and 2,048
bytes. Companion free lists use the heads of the power classes below 64 bytes,
which no block can use. Each class is a multiple of 16 bytes, so a heap
starting at 64 KiB keeps 16-byte aligned payloads. Checked type roles
resolve dynamic value fields before counting. Table-function and List
owner-token words are scalars. Numeric arrays and List leaves have zero-child
descriptors.

Zero-byte typed allocation returns null and acquires no lease. Allocation
initializes reference payloads before publication. Each nonempty allocation
starts with one explicitly counted tracer lease; every owning field adds its own
count. Stores retain the replacement, publish, then release the old edge.
Numeric Array elements have zero-child layouts, so element writes are checked
scalar stores. They skip the `store_word` layout lookup but keep the bounds
check. Self-stores preserve the count. Copies check the destination range once,
preserve overlap direction and account for every changed reference slot;
identical slots need no count change. Scalar copies use the original bulk-copy
path.

Retain checks overflow; releases check live storage and nonzero counts. Zero
counts enter an allocation-free header queue. Destruction detaches outgoing
fields, decrements children and recycles each object once. It never calls back
into source or host code. The Wasm call depth stays constant for a million-node
chain. Zero-child destruction does not scan the payload.

List descriptors own root and cache edges. Branches own both children; reference
leaves own initialized elements and scalar leaves own none. Spare leaf words
remain zero. Allocation classes determine capacity: a 1024-byte block minus the
32-byte arena header and 16-byte node header leaves 244 words. Shared
descriptor/cache edges count independently; odd owner tokens never retain an
obsolete descriptor. Reference Array construction and persistent updates use
typed allocation, stores and copies before scalar vectorization can erase roles.

## Counted leases and tracing

This stage does not claim a complete root journal. Existing allocation groups
drop each member's lease once, including normal returns and proven exit edges.
Unproven local/returned aliases retain their lease until a tracer safe point.
The lease is a real strong owner, not an uncounted exception.

The tracer establishes its complete dead set before retirement. Internal dead
edges disappear with that set; outgoing live edges decrement normally. It
retires dead leases through the same destructor and drains queued zero-count
children afterwards. Physical block sizes remain available for enumeration;
allocator links are never owning fields. Entry reset retires counted storage
before rewinding. A trap leaves its graph leased until that reset; it cannot
cause duplicate retirement during recovery.

The `blot:ownership` custom section contains revision 1, a counted-mode byte and
a fallback byte. Fallback codes are 0 admitted, 1 no arena, 2 public Array
arena, 3 host references, 4 imports, 5 startup initializer, 6 mutable static
sequence caches and 7 unproven machine body. All bodies must admit together.
Fallback modules keep tracing behavior, with counting disabled in typed helpers.
The emission recorder owns one Arena descriptor, with a journal marker; ordinary
instruction records do not carry its growing helper payload. Optimizer records
share their capture's exact Arena context. The matcher checks that complete
context before either positional or relocated reuse. Fragment admission and
replay use the same complete owned arena-global list; the diagnostic counters
cannot silently prevent retained source reuse.

Four declared diagnostic globals expose leases, retains, releases and destroyed
objects. Guest validation requires the complete set and rejects malformed,
duplicate or inconsistent manifests.

Persistent global/demand roots and ABI Array ownership remain with 032; Foreign
and JSPI modules remain with 033. The tracer still handles cycles. Candidate
queues and localized trial deletion belong to 034. Neither current source
admission nor kernel execution qualifies removal of tracing.

## Qualification

Native laws sweep every allocation failure for IR preparation and real source
List/Array construction/publication, preserving immutable inputs and frozen
Core. Guest laws cover duplicate fields, self-store, edge replacement, scalar
pointer bits, overflow and repeated release, shared collection nodes, traced
cycles with a live outgoing child and a million-node acyclic chain. Both codegen
tiers admit source Array/List snapshots and immediate Array alias-group
destruction; trap recovery returns lease counts to zero. Existing Array, packed
List, ownership role, staged flow, State/demand cycle memory and Foreign-array
laws also run.

Release compiler, reference-operation and header costs are qualified separately.
Measurements must identify host load and exact compiler/workload hashes; debug
development times are not release evidence. Full compiler qualification and
remaining costs must be recorded before declaring this task complete.

## Release comparison, 11 October 2026

The incoming tracing tree is `cae61473ec51165235544702e78c5da19d2ee67a`. Its
release compiler is SHA-256
`3b90d1620111047246b34f16ad5762cd53daa0e8dc8dd6cce3b3fbb5e451304a`; the measured
candidate is `6520c0b30cf6acdf12cf20eb347313aa8afe88f9a98dbca88965b200c1f0fb56`.
The final native-law correction changes only test source and compiler identity;
its release compiler is
`c072c67a05f2397f07a03e35ef031ae4ed5efdf083828eb69bf8a775538239af`. Three
fresh/edit identity pairs preserve native work counts and the measured
workload's exact Wasm bytes. Both use Zig 0.17.0, `-Doptimize=fast` and LLVM.
Restart caches are disabled. The reference workload constructs dynamic child
Arrays, persistent Array/List snapshots and reference-valued List-to-Array
copies; it returns scalar results. Both candidate functions admit counting. The
source SHA-256 is
`daf5c3d165646874f84c6705ffd66f02eab2583f8d2d2dbb6e4f600a2def7e8f`.

Twenty alternating compiler pairs after two warmups preserve every native work
count. Median process CPU is 7.262 → 7.549 ms fresh and 2.692 → 3.047 ms
retained edit: +3.9% and +13.2%. Twenty alternating runtime pairs after five
warmups, each with 2,000 invocations, measure 0.217 → 0.904 ms for Array
snapshots and 2.897 → 32.956 ms for List snapshots. These include actual field
publication and counted lease retirement at entry reset. The costs are material:
4.2 and 11.4 times tracing CPU. They do not qualify the later tracing-removal
budget. Host load averages were approximately 4.6 during these batches; other
compiler jobs were present. A separate million retain/release-pair probe
measures 17.114 ms for empty Wasm calls and 23.348 ms for checked operations,
about 6.2 ns additional CPU per pair. This isolates operation checks from
collection geometry and does not predict whole-program costs.

Header growth affects fallback modules too. Public-Array allocation probes in
this release showed 4-, 8- and 16-byte payloads moving from 32- to 64-byte
blocks; 24-, 32-, 64-, 976-, 992-, 1,024- and 4,096-byte payloads kept their
previous classes. The later companion classes put 4- to 16-byte payloads in
48-byte blocks, 64-byte payloads in 96-byte blocks and 1,024-byte payloads in
1,536-byte blocks; the other probed payloads keep the classes above. The List
leaf boundary is now 244 words, with source laws across that boundary at all row
widths; old 248-word evidence is historical. A 100,000-element numeric
List-to-Array probe commits 1,048,576 bytes in both releases. Page equality does
not erase the smaller-object/header overhead.

The existing State/strong-memo cycle and ordinary forever-loop memory laws pass.
The historical 90-row nested traversal counterexample remains unresolved in both
releases: 8, 40 and 200 discarded 8,192-word Arrays per row commit 43,515,904,
203,816,960 and 942,211,072 bytes. Its public Array entry selects whole-module
fallback. This is neither a bounded-memory result nor evidence for tracer
removal. It remains a mandatory counterexample for the
[List traversal memory gate](LIST_TRAVERSAL.md) and
[tracing replacement qualification](TRACING_REPLACEMENT.md).

The final release build, full native suite and all 771 guest/client laws pass.
The unchanged eight compile allocation budgets pass with restart caches
disabled. The analyzer reports zero findings across 327 Zig files. Native laws
include OOM/immutable-input, artifact/archive and retained-candidate equality.
Ownership directives still erase from scalar/no-allocation Wasm; a separate law
checks that typed allocations select counted metadata while unknown roles retain
the tracing fallback. Guest laws include seven counted RC laws and all current
244-word boundaries. These checks qualify the 031 transition, not complete root
coverage or tracing removal. Joint integration at `cb41a6d` passes the same full
gate and all eight unchanged allocation budgets, with zero analyzer findings
across 327 files. The main release SHA-256 is
`1ea2d0594b5dcbd183d807844867f07a02af6172a9c0ffff8dfb604414201a19`; its source
fingerprint is
`5f77e785613b0d595ce91247a4a3877fbd337ae4e49d5228df73f34aacf715f6`, identical to
the isolated qualified compiler. Binary differences include build paths; source
changes were compared exactly before integration. Raw paired distributions,
exact Wasm/compiler hashes, load samples and geometry reports are kept in the
ignored `build/bench/shared-rc/` qualification directory.

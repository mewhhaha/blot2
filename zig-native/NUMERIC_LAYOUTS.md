# Numeric values and collection storage

The language type and its physical collection row are separate. A numeric record
keeps its named fields, and a data constructor keeps its nominal identity.
Packing does not introduce mutation or change the order of floating-point
operations.

## Admitted rows

Arrays and Lists can store a checked numeric aggregate as consecutive 32-bit
scalar words. A bounded plan follows products, records, and public, non-opaque
nominals with exactly one constructor. Every leaf must be Unit, Bool, U32 or
F32. The plan admits at most sixteen scalar leaves, thirty-two object nodes and
sixteen levels, and limits layout/constructor work to 256 visits. Empty rows,
references, callables, open layouts, capabilities, usage-qualified data, hidden
nominals, multiple constructors, or exhausted limits keep their ordinary
representation. Existing flat scalar rows retain their prior admission rules.

The plan uses checked layout IDs, constructor identity and physical field order.
Field names such as `x` or `matrix` grant no special treatment. It belongs to
one code generator, owns no inference-store pointers, caches both admission and
refusal, and is destroyed with that generator.

An Array has its ordinary length word followed by the packed rows. A List uses
its existing persistent tree with scalar leaf storage; logical row indices are
translated to physical words, and leaf boundaries preserve complete rows.
Conversion, concatenation, slicing, indexing and updates use the same stride.
Compile-time constants serialize exactly that representation, including record
field-name matching. Saved collection versions retain their original values.

## Calls, reads and lifetime

Outside a collection, an aggregate uses the ordinary boxed value ABI. Extracting
an owned row reconstructs its exact object tree, allocating children before
parents and preserving constructor tags and reference roles. No borrowed
interior address becomes a source value. F32 words move as raw bits.

A loop may read scalar fields directly from packed storage when checked use
analysis admits the complete projection path. This follows nominal and
structural nesting and forwards the view to a known immediate reader only when
its body passes the same check. Unknown calls materialize an owned value. Values
saved after a loop, deferred captures, non-scalar subobjects and unproved uses
keep normal ownership. The original collection remains the owner of every
borrowed physical read.

Generated rows use ordinary cleanup scopes in batches of at most 32. After a
batch has copied its scalar words, its temporary object graphs can be retired.
The destination and older captured objects remain owned by their enclosing
scope. Final partial batches and interrupted callbacks follow the same cleanup
rules.

Direct calls can expose numeric adapters with four to sixteen scalar leaves to
the existing scalar replacement pass. The larger body limit is eight nodes per
scalar leaf, capped at 128 nodes, with a separate 128-visit layout proof.
Ordinary inline limits remain unchanged. In particular, a one-word nominal
wrapper does not force unrelated helpers to inline. The optimizer still decides
whether exposed allocations disappear.

## Host boundaries and guarantees

Host cleanup data uses its checked logical schema to copy a packed row back to
ordinary immutable records, products and nominal values. It validates bounded
scalar row structure and constructor identity before decoding. Host copies keep
no guest aliases. Public call signatures and explicit wire encoders are not
replaced by the collection's physical row representation.

This is not an allocation-free annotation. A packed collection still allocates
storage, and constructors, escaping values, unknown callbacks and runtime
helpers can allocate. Pre-optimization allocation remarks alone cannot certify
an allocation-free call boundary. Such a guarantee would need a separate checked
transitive proof and must refuse unknown callees and unproved runtime
allocation.

## Qualification

The focused `numeric-aggregates` development family covers imported calls, both
codegen tiers, scalar bit/order witnesses, increasing collection sizes, nested
edits, saved snapshots, unknown callbacks, escaped values, captured producers,
interrupted generation, source/archive host copying, and
fresh/edit/rejection/recovery/revert equality. Planner/cache and emission tests
also run exhaustive allocation-failure sweeps separately from sampled checks.

`scripts/bench_numeric_aggregates.ts` compares compile CPU/RSS, Wasm size,
executed allocation traffic, capacity and runtime separately. It requires eager,
fixed-tier V8 compilation so background tiering cannot enter runtime samples.
Runtime timings call scalar Wasm exports inside their ownership boundary; the
public `guest.call` adapter validates the same results separately. Allocation
instrumentation is not used for timing. Private application performance and
final compiler qualification remain separate gates; the focused suite does not
replace them.

## Final qualification, 23 October 2026

The [integrated LLVM qualification](NUMERIC_QUALIFICATION.md) compares against
released main, publishes seven-pair measurements in both codegen tiers and
records the complete compiler gate. The development comparison below is
historical evidence for the earlier storage-only candidate.

## Development comparison, 23 October 2026

The [raw report](measurements/numeric-storage-development-2026-10-23.json.gz)
pins both native-backend compiler executables, the synthetic sources, standard
library, harness and machine. Seven alternating pairs ran in each codegen tier.
The baseline is the integrated candidate before recursive collection storage,
not an independent qualification against released main. The final LLVM and
private application comparison is recorded separately above.

For a generated array of 512 sixteen-F32 rows, warmed arena capacity changes
from 256 to 192 KiB for nested structural rows and from 320 to 192 KiB for
nested nominal rows. Both flat forms use 192 KiB before and after. These are
capacity measurements, not live payload or process RSS.

| Representation    | Rounded arena bytes per call, before |  After | Optimized runtime paired CPU ratio |
| ----------------- | -----------------------------------: | -----: | ---------------------------------: |
| Nested structural |                               151552 | 188416 |                              1.020 |
| Flat structural   |                               122880 | 122880 |                              1.014 |
| Nested nominal    |                               294912 | 311296 |                              0.998 |
| Flat nominal      |                                90112 | 139264 |                              0.918 |

The allocation counter includes recycled storage. Temporary construction and
packing can increase cumulative traffic while reducing retained capacity. The
runtime comparison uses raw scalar Wasm calls with ordinary ownership entry and
exit, eager fixed-tier V8 compilation, and three batches per sample. Samples
still vary, so the near-parity rows do not establish a speedup. Development-tier
paired ratios are 1.029, 1.022, 0.987 and 0.884 in the same order.

For the complete synthetic module, median compiler CPU is 371.7 to 369.2 ms in
the development tier and 402.3 to 450.9 ms in the optimized tier. Peak compiler
RSS changes from 47.2 to 48.9 MiB and 47.6 to 49.6 MiB, respectively. Expanded
boxing/unboxing code increases Wasm size. This cost must be checked against the
application workload before release; allocation counts alone do not qualify it.

# Private static execution and image metering

This scratch-only path extends the independently reviewed ordered target
fixture. It executes its retained scalar trees with explicit charges before
F32 literal conversion, arithmetic, NaN classification, serialization calls,
and selected byte reads/writes in the helper. It also charges before the
scalar value-buffer creation, value writes, output-buffer creation and writes,
image-data copying, and byte-by-byte image/value comparison. `static_om_float`
charges the actual control flow; it does not replay estimated work. Each
charge is an event in this fixture's private accounting policy, not a claim
that C09 specifies this exact cost table. F32 remains governed by the existing
host IEEE binary32 and rounding assumptions.

The ordered source and target portions retain the limitations documented in
`static_ot_SCOPE.md`. Hidden vector growth, dynamic allocator work, internal
`bytes_of`/`from_bytes` copying and allocation, the source held by the image,
metadata and layout inspections not explicitly instrumented here, and other
compiler type/proof/resource/manifest/package phases remain unmetered. This is
not complete C09 accounting, a canonical resource receipt, a public ABI,
Domain authority, or general K1 compiler admission. The work meter and
source-owned checked input are compiler-owned trusted state. No performance
improvement is claimed.

Focused tests compare primitive F32 bits against the existing implementation,
exercise every fixture work cutoff through each helper, compare complete
pipeline target bytes over 120 generated inputs, check every semantic cutoff
for one complete compilation, and execute the emitted Wasm at O0/O2. A
multi-page target comparison exercises the inherited emitter and checker
separately, not the full pipeline.

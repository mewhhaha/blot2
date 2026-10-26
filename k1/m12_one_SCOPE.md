# Private one-module aggregate adapter experiment

This fixture emits an import-free WebAssembly module for a checked, bounded I08
particle kernel and one checked source adapter. A compiler-emitted internal
shim connects the adapter's by-reference aggregate interface to the existing
frame-protected worker in the same module. The source adapter and linked kernel
are revalidated against the exact caller-supplied module before emission. The
target checker verifies complete module structure, source-associated worker
bodies, independently pinned frame bodies, and pinned shim and adapter bytes.
It is a closed target witness, not a general Wasm validator.

The argument record contains five words in source order: input View data and
length, F32 `dt`, and destination data and capacity. The Result slot contains the
success tag, Nat witness, and output View data and length. Empty output has zero
data and length. This fixture uses one owner, at most eight rows, a configured
and entered frame with old frontier zero, and fixed scratch addresses. The
frame reservation is [49152, 49920); its scratch tuple is [49152, 49176) and
returned View slot is [49184, 49192). Caller record and Result slots must be
aligned, mutually disjoint, and contained in the remainder of the reservation.

Numeric checks do not provide unforgeable capabilities. The caller must supply
exclusive, authentic, same-instance owner, descriptors, live loans, and frame
authority and must not mutate state concurrently. The fixture does not derive
those claims from arbitrary source or a public host call.

The adapter publishes its Result only after worker completion and return checks.
A trap leaves a valid Result slot unpublished, but the worker can have written
partial output or left runtime state live; the caller must discard the instance.
This experiment does not convert traps to `#Err` or establish general cleanup,
dynamic frame allocation, K1 resource/effect qualification, a public ABI, M12
manifest, or M13 admission. `m12_adapter_verify::public_eligible` remains false.

Tests cover exact-source and target corruption, forged proof records, alternate
kernel expressions, slot boundaries, zero and populated output, input
preservation, and failures. Independent checks compare worker and pinned frame
bodies and exercise F32 values and a partial-write trap. These checks rely on
the trusted-session assumptions above and do not establish general compiler
completeness or a speed comparison.

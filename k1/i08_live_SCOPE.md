# Private source-to-live-Wasm witness

This fixture checks one fixed particle source through `i08_link`, its
source-local capability trace and affine-site plan, then independently checks
the emitted Wasm target. An enclosed, single-use host authority creates its
own fresh Wasm instance, reserves one owner, copies and freezes the input,
allocates a fixed-capacity disjoint builder, checks the instance's actual
owner/bitmap/descriptor metadata and input bytes, and calls the worker once.
On success it copies the result into host-owned memory, ends both fixture
logical descriptors and closes the owner. Forged metadata or injected traps
discard the entire fresh instance; this is not evidence of K1 cleanup after a
trap. Test faults are artificial and not source-level error results.

The host adapter and allocator/descriptor implementation are trusted, as are
private memory, nonconcurrent input and untampered JS intrinsics. The source
model's formal Region IDs are syntactically distinct; mapping them to one
physical owner depends on the fixture's separately checked disjoint ranges
and assumed input/output loans. Those checks do not prove general source loan
authority. Numeric IDs, model receipts or values supplied by the host do not
confer authority. This private witness does not admit a general program, M12
manifest or public ABI. It does not implement host frame preflight, source
capability authenticity, general alias-return results, source-level errors or
complete arithmetic-NaN qualification. Frame/stack and Wasm trap isolation
remain external assumptions.

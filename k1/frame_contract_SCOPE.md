# Conditional fixed-target frame model

This private model rechecks the exact source and full independently pinned
invocation target, then checks fixed tuple, View, record, Result and reserved
kernel spans for bounds, overflow and overlap, including empty Unit spans. It
checks that the exact source declares kernel depth/frame 2/256 and adapter
3/512. It conservatively compares a 176-byte wrapper span plus the adapter's
512-byte declaration against the 768-byte reservation, and records a
six-function emitted Wasm call path. The numeric depth 4 is only source
contract arithmetic; it is not a qualified complete call-depth bound.

The fixed adapter uses absolute frame slots and requires incoming frontier
zero. A separate guarded invocation returns FrameLimit before owner
reservation, input copy or source effects when the frontier is nonzero.

`qualified` is deliberately always false: the plan does not mechanically
prove every machine load/store corresponds to the modeled slots, classify the
canonical-to-flattened shim and helper calls for M11 resource composition, or
prove all helper frame requirements. Engine stack capacity, the canonical
public ABI, source loan/capability identity, general result layouts, true trap
cleanup and arbitrary source resource certification remain external. This is
not public M11/M12 admission.

# Private source-resource and partial frame-access composition

The fixed source gate checks the exact kernel and adapter, target bytes, and
conditional frame-plan fields. The linked test combines those source resource
values with the independently pinned Wasm control-flow and fixed-context
adapter/shim slot checks. It verifies declared kernel depth/frame 2/256 and
adapter 3/512, checks the conservative arithmetic 176+512=688 <= 768 and
checks that the selected actual adapter/shim accesses stay in their fixed
slots and avoid the reserved kernel span.

This fixture does not qualify M11: the source wrapper's depth 4 is arithmetic,
not a verified callable bound; helper/adapter call classification, helper
frame effects, and caller/worker dynamic accesses remain unchecked. The
resource sidecar is forgeable and never a bearer capability. Exact source/target
generation, trusted JS intrinsics, private memory and nonconcurrency are
preconditions. The source-local loans, public ABI, frame sufficiency, typed trap
cleanup and engine stack are not established. Public eligibility stays false.

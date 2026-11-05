# Wasm optimization writing record

Writing only. No builds, tests, formatter checks, compiler invocations or
verification ran. Native regression sources remain unchanged as the oracle.

Full production first writing passes: wasm_bit_recurrence, wasm_bulk_loop,
wasm_copy_coalesce, wasm_inline, wasm_lane_loop, wasm_local_compact,
wasm_merge_loop, wasm_row_products, wasm_row_reduce, wasm_stackify,
wasm_stride_reduce, wasm_transport_cleanup, wasm_vectorize.

Remaining assigned production passes: wasm_scope_outline, wasm_sroa.

Bodies use const Module getters for Range-backed Function views, including
borrowed detached bodies. Completed transforms return actual owned IR
DetachedBody values. Shared optimizer_buffers provides concrete typed temporary
owners with explicit cleanup. Scalar expression recipes in loop emitters are
written as complete postfix Wasm instructions, preserving guard and fallback
instruction order. No source name, spelling, or unproved representation grants
optimization authority.

Private process workers own their callee Facts cells. The native atomic bit
memoization becomes ordinary monotonic bit OR in that isolated process; no Goose
thread shares those cells. Inline retains complete adapter control/role proof,
bounded forwarding and framing, checked zero initialization, relocated ownership
annotations, original call position, and two bounded expansion steps.

Loop rewrites keep ordinary source owner/effect/backedge checks in the caller;
runtime guards retain exact scalar fallback, owner validation order, valid-prefix
writes and live-out cursor updates. Recurrence proofs retain fixed work/depth
limits and exact wrapping bit algebra. Vectorization preserves scalar tail
instructions and rejects effects, traps, invalid private locals and unknown
machine operations. Copy coalescing retains scopes, write versions, helper tree
admission and every-read forwarding before removing a destination.

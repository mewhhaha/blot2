//! Independently compiled evaluator laws.
comptime {
    _ = @import("check/core_proof_tests.zig");
    _ = @import("check/core.zig");
    _ = @import("check/core_tests.zig");
    _ = @import("check/core_aggregate_tests.zig");
    _ = @import("check/core_closure_tests.zig");
    _ = @import("check/core_array_tests.zig");
    _ = @import("check/core_callable_tests.zig");
    _ = @import("check/core_loop_tests.zig");
    _ = @import("check/core_update_tests.zig");
    _ = @import("check/core_demand_tests.zig");
    _ = @import("check/core_monad_tests.zig");
    _ = @import("backend/loop_targets_tests.zig");
    _ = @import("eval/core_eval.zig");
    _ = @import("eval/core_eval_tests.zig");
    _ = @import("eval/scope_components.zig");
    _ = @import("eval/core_operation_evidence_tests.zig");
    _ = @import("eval/builtin_state_tests.zig");
    _ = @import("eval/reflection_tests.zig");
    _ = @import("backend/scalar_ops.zig");
    _ = @import("eval/core_request_tests.zig");
    _ = @import("eval/eval_collection_growth.zig");
    _ = @import("backend/core_dispatch_tests.zig");
}

//! Ordinary schemes own their assumptions. Publication follows every endpoint;
//! executable uses must additionally reconstruct the operation under that goal.
const C = @import("package_contracts.zig");
const Error = error{InvalidArtifact};
pub fn scope(context: *C.Context, goals: anytype) Error!void {
    for (goals) |goal| {
        if (context.remaining.* == 0) return error.InvalidArtifact;
        context.remaining.* -= 1;
        inline for (.{ "ty", "other", "result", "signature" }) |field| {
            const endpoint = @field(goal, field);
            if (endpoint != 0) try context.visit(endpoint);
        }
        if (goal.identity.unit == 0 and goal.identity.decl != 0 and goal.kind != .contract) try context.visit(goal.identity.decl);
    }
}

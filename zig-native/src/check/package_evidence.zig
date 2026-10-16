//! Canonical evidence owns sorted binders and lexical-depth references.
//! The caller first checks all table spans and backward edges. Canonical sharing
//! of one ordinal between different recipes is legal; free roots are not.
const E = @import("../eval/type_evidence.zig");
const Error = error{InvalidArtifact};
pub fn validate(source: E.View) Error!void {
    if (source.nodes.len > 4096) return error.InvalidArtifact;
    var remaining: usize = 65_536;
    source.validateGoalTablesWithBudget(&remaining) catch return error.InvalidArtifact;
    var seen: [4096]bool = @splat(false);
    for (source.nodes, 0..) |node, id| {
        if (node.tag != .forall and node.tag != .existential) continue;
        if (node.a == 0 or node.a >= id or node.b == 0 or node.b > 128 or node.c > source.extra.len or node.b > source.extra.len - node.c) return error.InvalidArtifact;
        if (node.tag == .existential) for (source.children(@intCast(id))) |binder| if (source.node(binder).b != 0) return error.InvalidArtifact;
        source.openQuantifierValidated(@intCast(id), &remaining, &seen) catch return error.InvalidArtifact;
    }
    for (source.nodes, 0..) |node, id| if ((node.tag == .bound or node.tag == .projection) and !seen[id]) return error.InvalidArtifact;
}

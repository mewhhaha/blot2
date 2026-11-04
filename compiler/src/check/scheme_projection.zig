//! Resolve a closed associated endpoint only through the called declaration's
//! required goal and an already admitted exact selected type member.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const C = @import("package_contracts.zig");
const Error = error{InvalidArtifact};
fn require(ok: bool) Error!void {
    if (!ok) return error.InvalidArtifact;
}
fn charge(remaining: *usize) Error!void {
    try require(remaining.* != 0);
    remaining.* -= 1;
}
pub const Resolver = struct {
    module: *const core.Module,
    producer: *const core.Module,
    binding: core.BindingId,
    applied: ?*const C.Principal = null,
    pub fn resolver(self: *Resolver) C.PrincipalProjectionResolver {
        return .{ .context = self, .validate = validate };
    }
    fn validate(raw: *anyopaque, mapping: *C.Principal, expected: T.Id, actual: T.Id) Error!void {
        const self: *Resolver = @ptrCast(@alignCast(raw));
        const owner_mapping = self.applied orelse mapping;
        try require(owner_mapping.left == &self.producer.types and owner_mapping.right == &self.module.types and mapping.right == &self.module.types);
        try require(self.binding != 0 and self.binding < self.producer.bindings.len);
        const callee_declaration = self.producer.binding(self.binding);
        const scheme = callee_declaration.scheme;
        const source_public = if (mapping.views) |views| views.source_instances and views.large_plain_graph and
            self.producer.types.node(scheme.root).tag != .forall and (scheme.variables.len > 128 or scheme.row_variables.len > 128) else false;
        const endpoint_variables = if (source_public) callee_declaration.public_variables else scheme.variables;
        const endpoint_rows = if (source_public) callee_declaration.public_rows else scheme.row_variables;
        try require(std.meta.eql(owner_mapping.instance, endpoint_variables) and std.meta.eql(owner_mapping.instance_rows, endpoint_rows));
        const projection = mapping.left.node(expected);
        try require(projection.tag == .projection);
        const arguments = mapping.left.nominalArguments(projection);
        const member_name = mapping.left.projectionMember(projection);
        // Candidate comparison cannot publish row certificates into its caller.
        const views = mapping.views orelse return error.InvalidArtifact;
        const pure_rows = views.pure_rows;
        const closed_rows = views.closed_rows;
        defer views.pure_rows = pure_rows;
        defer views.closed_rows = closed_rows;
        for (self.producer.obligations[scheme.obligations.start..][0..scheme.obligations.len]) |goal| {
            try charge(mapping.remaining);
            views.pure_rows = pure_rows;
            views.closed_rows = closed_rows;
            if (goal.kind != .contract or goal.identity.unit != projection.a or goal.identity.decl != projection.b) continue;
            const tuple = self.producer.types.node(goal.ty);
            if (tuple.tag != .product or tuple.b != arguments.len) continue;
            const required = self.producer.types.list(.{ .start = tuple.a, .len = tuple.b });
            var owned: C.Principal = .{ .left = &self.producer.types, .right = &self.producer.types, .remaining = mapping.remaining, .left_rows = scheme.closed_rows };
            if (self.applied != null) {
                owned = owner_mapping.*;
                owned.foreign_views = false;
            }
            var matches = true;
            for (required, arguments) |clause, argument| {
                owned.validate(clause, argument) catch {
                    try require(mapping.remaining.* != 0);
                    matches = false;
                    break;
                };
            }
            if (self.applied != null and (!std.meta.eql(owned.witnesses, owner_mapping.witnesses) or !std.meta.eql(owned.scheme_row_witnesses, owner_mapping.scheme_row_witnesses))) matches = false;
            if (!matches) continue;
            for (self.module.selected_proofs) |proof| {
                try charge(mapping.remaining);
                views.pure_rows = pure_rows;
                views.closed_rows = closed_rows;
                if (proof.kind != .implementation or proof.contract.unit != goal.identity.unit or proof.contract.decl != goal.identity.decl or proof.arguments.len != arguments.len) continue;
                var comparison = owner_mapping.*;
                comparison.foreign_views = false;
                matches = true;
                for (required, self.module.types.list(proof.arguments)) |clause, selected| {
                    comparison.validate(clause, selected) catch {
                        try require(mapping.remaining.* != 0);
                        matches = false;
                        break;
                    };
                }
                // An associated result cannot choose a previously unknown head.
                if (!matches or !std.meta.eql(comparison.witnesses, owner_mapping.witnesses) or !std.meta.eql(comparison.scheme_row_witnesses, owner_mapping.scheme_row_witnesses)) continue;
                const declaration = for (self.module.contracts) |candidate| {
                    try charge(mapping.remaining);
                    if (std.meta.eql(candidate.identity, goal.identity)) break candidate;
                } else return error.InvalidArtifact;
                try require(declaration.members.len == proof.members.len);
                for (self.module.contract_members[declaration.members.start..][0..declaration.members.len], self.module.selected_members[proof.members.start..][0..proof.members.len]) |member, selected| {
                    try charge(mapping.remaining);
                    if (member.name != member_name) continue;
                    try require(member.kind != .value and selected.kind == .type_ and selected.name == member_name);
                    var endpoint: C.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = mapping.remaining, .views = mapping.views };
                    return endpoint.validate(selected.root, actual);
                }
                return error.InvalidArtifact;
            }
        }
        return error.InvalidArtifact;
    }
};

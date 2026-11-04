//! Dictionary slots belong to an immutable quantifier or named principal.
//! Ordinary inferred requirements retain their scheme owner at runtime.
const core = @import("core.zig");
const T = @import("types.zig");
const C = @import("package_contracts.zig");
const Error = error{InvalidArtifact};
pub const Owner = union(enum) {
    quantified: T.Id,
    scheme: core.BindingId,
    pub fn forBinding(module: *const core.Module, binding: core.BindingId) ?Owner {
        if (binding == 0 or binding >= module.bindings.len) return null;
        const principal = module.bindings[binding];
        if (principal.ty == 0) return null;
        var owner: Owner = .{ .scheme = binding };
        if (module.types.node(principal.ty).tag == .forall) owner = .{ .quantified = principal.ty };
        for (0..owner.count(module)) |ordinal| if (owner.goal(module, ordinal).kind == .contract) return owner;
        return null;
    }
    pub fn count(self: Owner, module: *const core.Module) usize {
        return switch (self) {
            .quantified => |id| module.types.quantifierGoals(id).len,
            .scheme => |id| module.bindings[id].scheme.obligations.len,
        };
    }
    pub fn goal(self: Owner, module: *const core.Module, ordinal: usize) core.Obligation {
        switch (self) {
            .quantified => |id| {
                const value = module.types.quantifierGoals(id)[ordinal];
                return .{ .ty = value.ty, .kind = value.kind, .span = .{ .start = 0, .end = 0 }, .name = value.name, .result = value.result, .other = value.other, .signature = value.signature, .operator = value.operator, .identity = value.identity, .explicit = value.explicit };
            },
            .scheme => |id| {
                const range = module.bindings[id].scheme.obligations;
                return module.obligations[range.start + ordinal];
            },
        }
    }
    pub fn formals(self: Owner, module: *const core.Module) T.List {
        return switch (self) {
            .quantified => |id| blk: {
                const node = module.types.node(id);
                break :blk .{ .start = node.b, .len = node.c };
            },
            .scheme => |id| module.bindings[id].scheme.variables,
        };
    }
    pub fn enter(self: Owner, module: *const core.Module, scopes: *C.Context) Error!void {
        switch (self) {
            .quantified => |id| try scopes.enter(id),
            .scheme => |id| try scopes.generic(module.bindings[id].scheme),
        }
    }
    pub fn instantiate(self: Owner, module: *const core.Module, proof: *C.Principal, actual: T.Id) Error!void {
        switch (self) {
            .quantified => |id| try proof.instantiateTypes(id, actual),
            .scheme => |id| try proof.instantiateScheme(module.bindings[id].scheme, actual),
        }
        const formals_ = module.types.list(self.formals(module));
        if (formals_.len > proof.witnesses.len) return error.InvalidArtifact;
        // A header must determine data witnesses before goal matching begins.
        for (formals_, proof.witnesses[0..formals_.len]) |formal, witness| {
            const leaf = module.types.node(formal);
            if (witness == 0 and (leaf.tag == .variable or (leaf.tag == .bound and leaf.b == 0))) return error.InvalidArtifact;
        }
    }
    pub fn canonicalGoal(self: Owner, module: *const core.Module, ordinal: usize, scopes: *C.Context) Error!usize {
        const value = self.goal(module, ordinal);
        if (value.kind != .contract) return error.InvalidArtifact;
        for (0..ordinal) |prior| {
            try step(scopes.remaining);
            const candidate = self.goal(module, prior);
            if (candidate.kind != .contract or candidate.identity.unit != value.identity.unit or candidate.identity.decl != value.identity.decl) continue;
            var proof: C.Principal = .{ .left = &module.types, .right = &module.types, .views = scopes, .remaining = scopes.remaining };
            proof.validate(value.ty, candidate.ty) catch {
                if (scopes.remaining.* == 0) return error.InvalidArtifact;
                continue;
            };
            return prior;
        }
        return ordinal;
    }
    pub fn offset(self: Owner, module: *const core.Module, wanted_goal: usize, wanted_member: usize, remaining: *usize) Error!usize {
        if (wanted_goal >= self.count(module)) return error.InvalidArtifact;
        var offset_: usize = 1;
        for (0..self.count(module)) |ordinal| {
            try step(remaining);
            const value = self.goal(module, ordinal);
            if (value.kind != .contract) continue;
            const contract = for (module.contracts) |candidate| {
                try step(remaining);
                if (candidate.identity.unit == value.identity.unit and candidate.identity.decl == value.identity.decl) break candidate;
            } else return error.InvalidArtifact;
            for (module.contract_members[contract.members.start..][0..contract.members.len], 0..) |member, index| {
                try step(remaining);
                if (ordinal == wanted_goal and index == wanted_member) {
                    if (member.kind != .value) return error.InvalidArtifact;
                    return offset_;
                }
                if (member.kind == .value) offset_ += 1;
            }
        }
        return error.InvalidArtifact;
    }
};

fn step(remaining: *usize) Error!void {
    if (remaining.* == 0) return error.InvalidArtifact;
    remaining.* -= 1;
}

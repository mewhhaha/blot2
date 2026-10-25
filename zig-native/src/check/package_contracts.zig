//! Checked package substitution reads the existing immutable type graph. A
//! witness list does not authorize a payload whose representation disagrees.
const core = @import("core.zig");
const std = @import("std");
const T = @import("types.zig");
const Error = error{InvalidArtifact};
const limit = 4096;
const Equations = @import("scheme_equations.zig");
fn require(ok: bool) Error!void {
    if (!ok) return error.InvalidArtifact;
}
pub fn foreign(types: *const core.Types, id: T.Effects.Id) bool {
    if (id >= types.effects.rows.len) return false;
    const row = types.row(id);
    if (row.tail != .closed or row.labels.len == 0) return false;
    for (types.rowLabels(id)) |label| if (label != T.foreign_operation) return false;
    return true;
}
pub fn pure(types: *const core.Types, id: T.Effects.Id) bool {
    if (id == 0 and types.effects.rows.len == 0) return true;
    if (id >= types.effects.rows.len) return false;
    const row = types.row(id);
    return row.tail == .closed and row.labels.len == 0;
}
fn span(types: *const core.Types, value: T.List) Error![]const T.Id {
    try require(value.start <= types.extra.len and value.len <= types.extra.len - value.start);
    return types.list(value);
}
fn projectionMember(types_: *const core.Types, node: T.Node) Error!u32 {
    try require(node.c < types_.extra.len);
    const start = @as(usize, node.c) + 1;
    const count = types_.extra[node.c];
    try require(count < types_.extra.len - start);
    const member = types_.extra[start + count];
    try require(member != 0);
    return member;
}
/// Raw foreign metadata supplies only closed monomorphic callables. A stored
/// universal or package needs the compiler's verified carrier/body authority.
pub fn quantified(types: *const core.Types, root: T.Id, remaining: *usize) Error!bool {
    return quantifiedDepth(types, root, remaining, 0);
}
fn quantifiedDepth(types: *const core.Types, root: T.Id, remaining: *usize, depth: usize) Error!bool {
    try require(root < types.nodes.len and depth < 128 and remaining.* != 0);
    remaining.* -= 1;
    const node = types.node(root);
    switch (node.tag) {
        .forall, .existential => return true,
        .function => return try quantifiedDepth(types, node.a, remaining, depth + 1) or try quantifiedDepth(types, node.b, remaining, depth + 1),
        .array, .list, .cursor, .usage, .demand, .resolver, .provider, .scoped => return quantifiedDepth(types, node.a, remaining, depth + 1),
        .state_provider => for ([_]T.Id{ node.a, node.b, node.c }) |child| if (try quantifiedDepth(types, child, remaining, depth + 1)) return true,
        .product => for (try span(types, .{ .start = node.a, .len = node.b })) |child| if (try quantifiedDepth(types, child, remaining, depth + 1)) return true,
        .record => {
            try require(node.b <= 0x7fff_ffff);
            _ = try span(types, .{ .start = node.a, .len = node.b * 2 });
            for (0..node.b) |index| if (try quantifiedDepth(types, types.recordField(node, index).ty, remaining, depth + 1)) return true;
        },
        .nominal => {
            try require(node.c < types.extra.len);
            for (try span(types, .{ .start = node.c + 1, .len = types.extra[node.c] })) |child| if (try quantifiedDepth(types, child, remaining, depth + 1)) return true;
        },
        else => {},
    }
    return false;
}
/// Reconstructs lexical authority from quantifier/opening ownership. Source
/// rigid nonces and equality of physical layouts never confer that authority.
/// Existing table validation remains responsible for nominal/effect catalogs.
pub const Context = struct {
    solver: ?*Equations.Solver = null,
    types: *const core.Types,
    remaining: *usize,
    owners: [limit]T.Id = @splat(0),
    pure_rows: @import("package_row_facts.zig").Facts = .{},
    closed_rows: @import("package_row_facts.zig").Facts = .{},
    formal: ?T.Id = null,
    generic_variables: T.List = .{},
    generic_rows: T.List = .{},
    obligations: []const core.Obligation = &.{},
    source_obligations: []const T.Obligation = &.{},
    schemes: [128]T.Scheme = undefined,
    scheme_count: usize = 0,
    formals: [128]T.Id = undefined,
    formal_count: usize = 0,
    introductions: [128]core.Id = @splat(0),
    witness: bool = false,
    representation_floor: ?usize = null,
    executable: bool = false,
    /// A checked source-body inquiry may contain unrelated ordinary types
    /// above the package reader's small tables. Lexical binders and row views
    /// still require their explicit bounds; this grants no package authority.
    large_plain_graph: bool = false,
    openings: [128]struct { binding: core.BindingId, binders: T.List, quantifier: T.Id } = undefined,
    projection_resolver: ?ProjectionResolver = null,
    opening_count: usize = 0,
    pub fn initialize(self: *Context) Error!void {
        try require(self.large_plain_graph or (self.types.nodes.len <= limit and self.types.effects.rows.len <= limit));
        try @import("quantifier_goals.zig").validateWithBudget(self.types.nodes, self.types.quantifier_goals, self.types.quantifier_obligations, self.remaining);
        for (self.types.nodes, 0..) |node, id| {
            if (node.tag != .forall and node.tag != .existential) continue;
            try require(id != 0 and node.c != 0 and node.c <= 128);
            for (try span(self.types, .{ .start = node.b, .len = node.c }), 0..) |binder, ordinal| {
                try require(binder < self.types.nodes.len and binder < self.owners.len);
                const leaf = self.types.node(binder);
                try require(leaf.tag == .bound and leaf.a == ordinal and leaf.b <= 2 and (node.tag == .forall or leaf.b == 0) and leaf.c == 0 and self.owners[binder] == 0);
                self.owners[binder] = @intCast(id);
            }
        }
        for (self.types.nodes, 0..) |node, id| {
            if (node.tag == .bound) {
                try require(id < self.owners.len);
                if (node.c == 0) try require(self.owners[id] != 0);
            }
        }
    }
    pub fn generic(self: *Context, scheme: T.Scheme) Error!void {
        self.generic_variables = .{};
        self.generic_rows = .{};
        self.scheme_count = 0;
        try self.pushGeneric(scheme);
    }
    pub fn pushGeneric(self: *Context, scheme: T.Scheme) Error!void {
        try require(self.scheme_count < self.schemes.len);
        self.schemes[self.scheme_count] = scheme;
        self.scheme_count += 1;
        if (self.types.node(scheme.root).tag == .forall) return;
        const variables = try span(self.types, scheme.variables);
        const rows = try span(self.types, scheme.row_variables);
        try require(variables.len <= 128 and rows.len <= 128);
        for (variables, 0..) |variable, ordinal| {
            try self.step(0);
            try require(variable < self.types.nodes.len and self.types.node(variable).tag == .variable);
            for (variables[0..ordinal]) |prior| try require(prior != variable);
        }
        for (rows, 0..) |row, ordinal| {
            try self.step(0);
            try require(row < self.types.effects.variable_count);
            for (rows[0..ordinal]) |prior| try require(prior != row);
        }
        self.generic_variables = scheme.variables;
        self.generic_rows = scheme.row_variables;
    }
    pub fn popGeneric(self: *Context) void {
        self.scheme_count -= 1;
        self.generic_variables = .{};
        self.generic_rows = .{};
        if (self.scheme_count != 0) {
            const scheme = self.schemes[self.scheme_count - 1];
            if (self.types.node(scheme.root).tag != .forall) {
                self.generic_variables = scheme.variables;
                self.generic_rows = scheme.row_variables;
            }
        }
    }
    pub fn ownsVariable(self: *Context, id: T.Id) Error!bool {
        for (self.schemes[0..self.scheme_count]) |scheme| {
            if (self.types.node(scheme.root).tag == .forall) continue;
            for (try span(self.types, scheme.variables)) |variable| {
                try self.step(0);
                if (variable == id) return true;
            }
        }
        return false;
    }
    pub fn ownsRow(self: *Context, id: u32) Error!bool {
        for (self.schemes[0..self.scheme_count]) |scheme| {
            for (try span(self.types, scheme.row_variables)) |variable| {
                try self.step(0);
                if (variable == id) return true;
            }
        }
        return false;
    }
    pub fn schemeGoals(self: *Context, scheme: T.Scheme) Error![]const core.Obligation {
        try require(scheme.obligations.start <= self.obligations.len and scheme.obligations.len <= self.obligations.len - scheme.obligations.start);
        return self.obligations[scheme.obligations.start..][0..scheme.obligations.len];
    }
    pub fn enter(self: *Context, owner: T.Id) Error!void {
        try require(self.formal_count < self.formals.len and owner < self.types.nodes.len);
        const node = self.types.node(owner);
        try require(node.tag == .forall or node.tag == .existential);
        self.formals[self.formal_count] = owner;
        self.introductions[self.formal_count] = 0;
        self.formal_count += 1;
        self.formal = owner;
    }
    pub fn leave(self: *Context) void {
        self.formal_count -= 1;
        self.formal = null;
        if (self.formal_count != 0) self.formal = self.formals[self.formal_count - 1];
    }
    pub fn ownsFormal(self: *const Context, leaf: T.Id) bool {
        if (leaf >= self.owners.len) return false;
        for (self.formals[0..self.formal_count]) |owner| if (self.owners[leaf] == owner) return true;
        return false;
    }
    fn region(self: *Context, id: T.Id, depth: usize) Error!void {
        try self.step(depth);
        try require(id < self.types.nodes.len);
        const leaf = self.types.node(id);
        // Lexical loans are independently checked by immutable usage admission.
        try require(leaf.tag == .bound and leaf.b == 2);
        try self.representationBinder(id);
        if (leaf.c == 0) try require(self.ownsFormal(id));
    }
    fn step(self: *Context, depth: usize) Error!void {
        try require(depth < 128 and self.remaining.* != 0);
        self.remaining.* -= 1;
    }
    pub fn visit(self: *Context, root: T.Id) Error!void {
        try self.walk(root, 0);
    }
    pub fn representation(self: *Context, root: T.Id) Error!void {
        const prior = self.representation_floor;
        self.representation_floor = self.formal_count;
        defer self.representation_floor = prior;
        try self.walk(root, 0);
    }
    fn representationBinder(self: *const Context, root: T.Id) Error!void {
        const floor = self.representation_floor orelse return;
        const node = self.types.node(root);
        try require(node.tag == .bound and node.c == 0 and root < self.owners.len);
        for (self.formals[floor..self.formal_count]) |owner| if (self.owners[root] == owner) return;
        return error.InvalidArtifact;
    }
    pub fn isForeign(self: *const Context, id: T.Effects.Id) bool {
        if (foreign(self.types, id)) return true;
        if (id >= self.types.effects.rows.len or !self.closed_rows.contains(id)) return false;
        const row = self.types.row(id);
        if (row.labels.len == 0 or row.tail != .variable) return false;
        for (self.types.rowLabels(id)) |label| if (label != T.foreign_operation) return false;
        return true;
    }
    pub fn isPure(self: *const Context, row: T.Effects.Id) bool {
        return pure(self.types, row) or (self.pure_rows.contains(row));
    }
    fn genericRow(self: *Context, id: T.Effects.Id, depth: usize) Error!bool {
        if (id >= self.types.effects.rows.len) return false;
        const row = self.types.row(id);
        if (row.tail != .variable) return false;
        try self.step(depth);
        return self.ownsRow(row.tail.variable);
    }
    pub fn validateRow(self: *Context, id: T.Effects.Id, depth: usize) Error!void {
        if (id == 0 and self.types.effects.rows.len == 0) return;
        try self.step(depth);
        try require(id < self.types.effects.rows.len);
        const value = self.types.row(id);
        if (value.tail == .formal) {
            const formal = value.tail.formal;
            try require(formal < self.types.nodes.len);
            const leaf = self.types.node(formal);
            if (leaf.tag == .rigid) {
                try require(self.solver != null and self.solver.?.ownsRigid(leaf) and leaf.c == 1);
            } else {
                try require(self.ownsFormal(formal) and leaf.tag == .bound and leaf.b == 1 and leaf.c == 0);
                try self.representationBinder(formal);
            }
        } else {
            var generic_row = false;
            if (value.tail == .variable) generic_row = try self.ownsRow(value.tail.variable);
            try require(value.tail == .closed or generic_row or self.isPure(id) or self.isForeign(id) or (self.closed_rows.contains(id)));
        }
        for (self.types.rowLabels(id)) |label| {
            try self.step(depth);
            try require(label != 0 and label < self.types.operations.len);
            const operation = self.types.operation(label);
            for (try span(self.types, operation.arguments)) |argument| try self.walk(argument, depth + 1);
            if (operation.instance.unit == 0 and operation.instance.decl != 0) try self.walk(operation.instance.decl, depth + 1);
        }
    }
    /// A method can retain its opening's evidence even when its arrow is closed.
    /// Only exact witnesses sealed by an enclosing pack discharge that footprint.
    pub fn goalFootprint(self: *Context, root: T.Id, owner: T.Id, opened: T.List, sealed: *const std.bit_set.Static(limit), depth: usize) Error!bool {
        try self.step(depth);
        const node = self.types.node(root);
        if (node.tag == .bound) {
            const quantifier = self.types.node(owner);
            const formals = try span(self.types, .{ .start = quantifier.b, .len = quantifier.c });
            try require(formals.len == opened.len);
            for (formals, self.types.list(opened)) |formal, witness| if (formal == root) return !sealed.isSet(witness);
            return false;
        }
        switch (node.tag) {
            .forall, .existential => {
                for (self.types.quantifierGoals(root)) |goal| inline for (.{ "ty", "other", "result", "signature" }) |field| {
                    const endpoint = @field(goal, field);
                    if (endpoint != 0 and try self.goalFootprint(endpoint, owner, opened, sealed, depth + 1)) return true;
                };
                return self.goalFootprint(node.a, owner, opened, sealed, depth + 1);
            },
            .function => {
                if (try self.goalFootprint(node.a, owner, opened, sealed, depth + 1) or try self.goalFootprint(node.b, owner, opened, sealed, depth + 1)) return true;
                return self.rowFootprint(node.c, owner, opened, sealed, depth + 1);
            },
            .usage => {
                if (node.c != 0 and try self.goalFootprint(node.c, owner, opened, sealed, depth + 1)) return true;
                return self.goalFootprint(node.a, owner, opened, sealed, depth + 1);
            },
            .demand, .provider => return try self.goalFootprint(node.a, owner, opened, sealed, depth + 1) or try self.rowFootprint(node.c, owner, opened, sealed, depth + 1),
            .array, .list, .cursor, .resolver => return self.goalFootprint(node.a, owner, opened, sealed, depth + 1),
            .state_provider => return try self.goalFootprint(node.a, owner, opened, sealed, depth + 1) or try self.goalFootprint(node.b, owner, opened, sealed, depth + 1) or try self.goalFootprint(node.c, owner, opened, sealed, depth + 1),
            .scoped => {
                if (try self.goalFootprint(node.a, owner, opened, sealed, depth + 1)) return true;
                return node.b == 0 and node.c != 0 and try self.goalFootprint(node.c, owner, opened, sealed, depth + 1);
            },
            .product => for (self.types.list(.{ .start = node.a, .len = node.b })) |child| {
                if (try self.goalFootprint(child, owner, opened, sealed, depth + 1)) return true;
            },
            .record => for (0..node.b) |index| {
                if (try self.goalFootprint(self.types.recordField(node, index).ty, owner, opened, sealed, depth + 1)) return true;
            },
            .projection, .nominal, .instance_selection => for (self.types.nominalArguments(node)) |child| {
                if (try self.goalFootprint(child, owner, opened, sealed, depth + 1)) return true;
            },
            else => {},
        }
        return false;
    }
    fn rowFootprint(self: *Context, row: T.Effects.Id, owner: T.Id, opened: T.List, sealed: *const std.bit_set.Static(limit), depth: usize) Error!bool {
        try self.step(depth);
        if (row == 0 and self.types.effects.rows.len == 0) return false;
        const value = self.types.row(row);
        if (value.tail == .formal and try self.goalFootprint(value.tail.formal, owner, opened, sealed, depth + 1)) return true;
        for (self.types.rowLabels(row)) |label| {
            try self.step(depth);
            const operation = self.types.operation(label);
            for (self.types.list(operation.arguments)) |argument| if (try self.goalFootprint(argument, owner, opened, sealed, depth + 1)) return true;
            if (operation.instance.unit == 0 and operation.instance.decl != 0 and try self.goalFootprint(operation.instance.decl, owner, opened, sealed, depth + 1)) return true;
        }
        return false;
    }
    fn projectionGoals(self: *Context, root: T.Id, goals: anytype, formals: T.List, opened: ?T.List, depth: usize) Error!bool {
        const projection_ = self.types.node(root);
        const arguments = self.types.nominalArguments(projection_);
        for (goals) |goal| {
            try self.step(depth);
            if (goal.kind != .contract or goal.identity.unit != projection_.a or goal.identity.decl != projection_.b) continue;
            const tuple = self.types.node(goal.ty);
            if (tuple.tag != .product or tuple.b != arguments.len) continue;
            var proof: Principal = .{ .left = self.types, .right = self.types, .remaining = self.remaining, .views = self };
            if (opened) |binders| {
                proof.instance = formals;
                @memcpy(proof.witnesses[0..binders.len], self.types.list(binders));
            }
            var matches = true;
            for (self.types.list(.{ .start = tuple.a, .len = tuple.b }), arguments) |expected, actual| {
                proof.match(expected, actual, depth + 1) catch |err| {
                    if (self.remaining.* == 0) return err;
                    matches = false;
                    break;
                };
            }
            if (matches) return true;
        }
        return false;
    }
    fn projectionGoal(self: *Context, root: T.Id, owner: T.Id, opened: ?T.List, depth: usize) Error!bool {
        const quantifier = self.types.node(owner);
        return self.projectionGoals(root, self.types.quantifierGoals(owner), .{ .start = quantifier.b, .len = quantifier.c }, opened, depth);
    }
    fn projection(self: *Context, root: T.Id, depth: usize) Error!void {
        _ = try projectionMember(self.types, self.types.node(root));
        for (self.types.nominalArguments(self.types.node(root))) |argument| try self.walk(argument, depth + 1);
        var scheme = self.scheme_count;
        while (scheme != 0) {
            scheme -= 1;
            const owner = self.schemes[scheme];
            if (owner.obligations.len == 0) continue;
            if (self.source_obligations.len != 0) {
                try require(owner.obligations.start <= self.source_obligations.len and owner.obligations.len <= self.source_obligations.len - owner.obligations.start);
                if (try self.projectionGoals(root, self.source_obligations[owner.obligations.start..][0..owner.obligations.len], .{}, null, depth + 1)) return;
            } else if (try self.projectionGoals(root, try self.schemeGoals(owner), .{}, null, depth + 1)) return;
        }
        var scope = self.formal_count;
        while (scope != 0) {
            scope -= 1;
            if (try self.projectionGoal(root, self.formals[scope], null, depth + 1)) return;
        }
        scope = self.opening_count;
        while (scope != 0) {
            scope -= 1;
            const opening = self.openings[scope];
            if (try self.projectionGoal(root, opening.quantifier, opening.binders, depth + 1)) return;
        }
        return error.InvalidArtifact;
    }
    fn walk(self: *Context, root: T.Id, depth: usize) Error!void {
        try self.step(depth);
        try require(root < self.types.nodes.len);
        const node = self.types.node(root);
        switch (node.tag) {
            .unit, .boolean, .u32, .f32, .never => {},
            .type_constructor => try require(!self.witness and node.c == 0),
            // Numeric admission independently checks positional proof recipes.
            // An erased slot cannot instantiate an existential data witness.
            .erased_proof => try require(!self.witness),
            .rigid => try require(self.solver != null and self.solver.?.ownsRigid(node)),
            .variable => {
                try require(try self.ownsVariable(root));
            },
            .bound => {
                try self.representationBinder(root);
                try require(node.b == 0);
                if (node.c == 0) {
                    try require(self.ownsFormal(root));
                    return;
                }
                for (self.openings[0..self.opening_count]) |opening| {
                    if (opening.binding != node.c) continue;
                    const binders = try span(self.types, opening.binders);
                    try require(node.a < binders.len and binders[node.a] == root);
                    return;
                }
                return error.InvalidArtifact;
            },
            .forall, .existential => {
                try require(!self.witness);
                try self.enter(root);
                defer self.leave();
                if (node.tag == .forall) try require(self.types.node(node.a).tag == .function);
                for (self.types.quantifierGoals(root)) |goal| {
                    inline for (.{ "ty", "other", "result", "signature" }) |field| {
                        const endpoint = @field(goal, field);
                        if (endpoint != 0) try self.walk(endpoint, depth + 1);
                    }
                }
                try self.walk(node.a, depth + 1);
            },
            .projection => try self.projection(root, depth + 1),
            .function => {
                try self.validateRow(node.c, depth + 1);
                try self.walk(node.a, depth + 1);
                try self.walk(node.b, depth + 1);
            },
            .usage => {
                try require(!self.witness);
                const loan = node.b == @backingInt(T.UsageKind.borrow) or node.b == @backingInt(T.UsageKind.borrow_mut);
                const cleanup = node.b == @backingInt(T.UsageKind.cleanup);
                if (cleanup) try require(self.formal == null);
                if (loan) try self.region(node.c, depth + 1);
                try require(loan == (node.c != 0));
                const concurrent = node.b == @backingInt(T.UsageKind.concurrent);
                if (concurrent) try require(@import("task_types.zig").concurrentHost(self.types, node.a));
                try require(loan or cleanup or concurrent or node.b == @backingInt(T.UsageKind.unique) or node.b == @backingInt(T.UsageKind.shared) or node.b == @backingInt(T.UsageKind.once) or node.b == @backingInt(T.UsageKind.many));
                try self.walk(node.a, depth + 1);
            },
            .scoped => {
                try require(!self.witness);
                try self.walk(node.a, depth + 1);
                if (node.b == 0) {
                    const identity = self.types.node(node.c);
                    if (identity.tag == .bound and identity.b == 2) try self.region(node.c, depth + 1) else try self.walk(node.c, depth + 1);
                }
            },
            .instance_version => try require(!self.witness),
            .instance_selection => {
                try require(!self.witness);
                const choices = self.types.nominalArguments(node);
                try require(choices.len == 2 or choices.len == 3);
                for (choices[0..2]) |choice| {
                    try require(self.types.node(choice).tag == .scoped);
                    try self.walk(choice, depth + 1);
                }
                if (choices.len == 3) {
                    try require(self.types.node(choices[2]).tag == .instance_version);
                    try self.walk(choices[2], depth + 1);
                }
            },
            .array, .list, .cursor, .resolver => try self.walk(node.a, depth + 1),
            .demand, .provider => {
                try require(!self.witness);
                try self.validateRow(node.c, depth + 1);
                try self.walk(node.a, depth + 1);
            },
            .state_provider => {
                try require(!self.witness);
                try self.walk(node.a, depth + 1);
                try self.walk(node.b, depth + 1);
                try self.walk(node.c, depth + 1);
            },
            .product => for (try span(self.types, .{ .start = node.a, .len = node.b })) |child| try self.walk(child, depth + 1),
            .record => {
                try require(node.b <= 0x7fff_ffff);
                _ = try span(self.types, .{ .start = node.a, .len = node.b * 2 });
                for (0..node.b) |index| try self.walk(self.types.recordField(node, index).ty, depth + 1);
            },
            .nominal => {
                if (@import("typed_staging.zig").isIdentity(node.a, node.b)) try require(self.formal == null and !self.witness);
                if (@import("typed_staging.zig").codeInfo(self.types, root)) |code_| {
                    try self.validateRow(code_.effects, depth + 1);
                    return self.walk(code_.result, depth + 1);
                }
                try require(node.c < self.types.extra.len);
                for (try span(self.types, .{ .start = node.c + 1, .len = self.types.extra[node.c] })) |child| try self.walk(child, depth + 1);
            },
            else => return error.InvalidArtifact,
        }
    }
    pub fn open(self: *Context, package: T.Id, binding: core.BindingId, binders: T.List, payload: T.Id) Error!void {
        try self.visit(package);
        const quantifier = self.types.node(package);
        try require(quantifier.tag == .existential and quantifier.c == binders.len and binding != 0 and self.opening_count < self.openings.len);
        for (self.openings[0..self.opening_count]) |opening| try require(opening.binding != binding);
        const witnesses = try span(self.types, binders);
        for (witnesses, 0..) |binder, ordinal| {
            try require(binder < self.types.nodes.len);
            const leaf = self.types.node(binder);
            try require(leaf.tag == .bound and leaf.a == ordinal and leaf.b == 0 and leaf.c == binding);
        }
        self.openings[self.opening_count] = .{ .binding = binding, .binders = binders, .quantifier = package };
        self.opening_count += 1;
        errdefer self.opening_count -= 1;
        try self.visit(payload);
        const proof: Substitution = .{ .types = self.types, .formal = .{ .start = quantifier.b, .len = quantifier.c }, .witnesses = witnesses, .remaining = self.remaining, .views = self };
        try proof.validate(quantifier.a, payload);
    }
    pub fn pack(self: *Context, package: T.Id, payload: T.Id, witnesses: []const T.Id) Error!void {
        try self.visit(package);
        const quantifier = self.types.node(package);
        try require(quantifier.tag == .existential);
        try self.visit(payload);
        self.witness = true;
        defer self.witness = false;
        for (witnesses) |witness| try self.visit(witness);
        const proof: Substitution = .{ .types = self.types, .formal = .{ .start = quantifier.b, .len = quantifier.c }, .witnesses = witnesses, .remaining = self.remaining, .views = self, .projection_resolver = self.projection_resolver };
        try proof.validate(quantifier.a, payload);
    }
    pub fn close(self: *Context) void {
        self.opening_count -= 1;
    }
};
pub const ProjectionResolver = struct {
    context: *anyopaque,
    validate: *const fn (*anyopaque, *const Substitution, T.Id, T.Id) Error!void,
};
pub const PrincipalProjectionResolver = struct {
    context: *anyopaque,
    validate: *const fn (*anyopaque, *Principal, T.Id, T.Id) Error!void,
};
pub const Substitution = struct {
    types: *const core.Types,
    formal: T.List,
    witnesses: []const T.Id,
    remaining: *usize,
    views: ?*Context = null,
    projection_resolver: ?ProjectionResolver = null,
    fn rowPure(self: *const Substitution, row: T.Effects.Id) bool {
        if (self.views) |views| return views.isPure(row);
        return pure(self.types, row);
    }
    fn step(self: *const Substitution, depth: usize) Error!void {
        try require(depth < 128 and self.remaining.* != 0);
        self.remaining.* -= 1;
    }
    pub fn validate(self: *const Substitution, expected: T.Id, actual: T.Id) Error!void {
        try require(self.formal.len == self.witnesses.len and self.formal.len != 0 and self.formal.len <= 128);
        for (try span(self.types, self.formal), 0..) |binder, ordinal| {
            try require(binder < self.types.nodes.len);
            const leaf = self.types.node(binder);
            try require(leaf.tag == .bound and leaf.a == ordinal and leaf.b == 0 and leaf.c == 0);
        }
        // Affinity belongs in the package's written interface. A type witness
        // cannot hide a unique owner, loan or once obligation in a plain `a`.
        for (self.witnesses) |witness| try require(!(@import("usage_check.zig").contains(self.types, witness) catch return error.InvalidArtifact));
        try self.match(expected, actual, true, 0);
    }
    fn match(self: *const Substitution, expected: T.Id, actual: T.Id, replace: bool, depth: usize) Error!void {
        try self.step(depth);
        try require(expected < self.types.nodes.len and actual < self.types.nodes.len);
        const left = self.types.node(expected);
        const right = self.types.node(actual);
        if (replace and left.tag == .bound) {
            for (try span(self.types, self.formal), self.witnesses) |binder, witness| {
                if (binder != expected) continue;
                return self.match(witness, actual, false, depth + 1);
            }
        }
        if (left.tag == .projection and right.tag != .projection and replace) {
            const resolver = self.projection_resolver orelse return error.InvalidArtifact;
            return resolver.validate(resolver.context, self, expected, actual);
        }
        try require(left.tag == right.tag);
        switch (left.tag) {
            .unit, .boolean, .u32, .f32, .never => {},
            // Open witnesses remain owned by an independently checked lexical
            // opening. Matching never equates separate opening identities.
            .bound => {
                try require(left.b == 0 and expected == actual);
                if (left.c == 0) {
                    const views = self.views orelse return error.InvalidArtifact;
                    try require(views.types == self.types and views.ownsFormal(expected));
                }
            },
            .forall, .existential => {
                var proof: Principal = .{ .left = self.types, .right = self.types, .remaining = self.remaining, .views = self.views, .instance = self.formal };
                @memcpy(proof.witnesses[0..self.witnesses.len], self.witnesses);
                try proof.validate(expected, actual);
            },
            .function => {
                var proof: Principal = .{ .left = self.types, .right = self.types, .remaining = self.remaining, .views = self.views };
                if (replace) {
                    proof.instance = self.formal;
                    @memcpy(proof.witnesses[0..self.witnesses.len], self.witnesses);
                }
                try proof.matchRow(left.c, right.c, depth + 1);
                try self.match(left.a, right.a, replace, depth + 1);
                try self.match(left.b, right.b, replace, depth + 1);
            },
            .usage => {
                try require(left.b == right.b and left.c == 0 and right.c == 0);
                try require(left.b == @backingInt(T.UsageKind.unique) or left.b == @backingInt(T.UsageKind.shared) or left.b == @backingInt(T.UsageKind.once) or left.b == @backingInt(T.UsageKind.many));
                try self.match(left.a, right.a, replace, depth + 1);
            },
            .array, .list, .cursor => try self.match(left.a, right.a, replace, depth + 1),
            .product => {
                try require(left.b == right.b);
                for (try span(self.types, .{ .start = left.a, .len = left.b }), try span(self.types, .{ .start = right.a, .len = right.b })) |a, b| try self.match(a, b, replace, depth + 1);
            },
            .record => {
                try require(left.b == right.b);
                try require(left.b <= 0x7fff_ffff);
                _ = try span(self.types, .{ .start = left.a, .len = left.b * 2 });
                _ = try span(self.types, .{ .start = right.a, .len = right.b * 2 });
                for (0..left.b) |index| {
                    const field = self.types.recordField(left, index);
                    var matched = false;
                    for (0..right.b) |other| {
                        try self.step(depth);
                        const candidate = self.types.recordField(right, other);
                        if (field.name != candidate.name) continue;
                        try self.match(field.ty, candidate.ty, replace, depth + 1);
                        matched = true;
                        break;
                    }
                    try require(matched);
                }
            },
            .nominal, .projection => {
                try require(left.a == right.a and left.b == right.b);
                if (left.tag == .projection) try require(try projectionMember(self.types, left) == try projectionMember(self.types, right));
                try require(left.c < self.types.extra.len and right.c < self.types.extra.len);
                const a = try span(self.types, .{ .start = left.c + 1, .len = self.types.extra[left.c] });
                const b = try span(self.types, .{ .start = right.c + 1, .len = self.types.extra[right.c] });
                try require(a.len == b.len);
                for (a, b) |x, y| try self.match(x, y, replace, depth + 1);
            },
            // No inferred, qualified, scoped, predicate or nested binder shape
            // gains authority just because its physical word happens to match.
            else => return error.InvalidArtifact,
        }
    }
};

/// Both consumers first reconstruct their lexical context. This comparison
/// only alpha-renames the two explicit quantifier owners currently compared.
pub const Principal = struct {
    left: *const core.Types,
    right: *const core.Types,
    remaining: *usize,
    formals: [128]struct { left: T.List, right: T.List } = undefined,
    formal_count: usize = 0,
    instance: T.List = .{},
    witnesses: [128]T.Id = @splat(0),
    row_witnesses: [128]?RowWitness = @splat(null),
    secondary: T.List = .{},
    secondary_witnesses: [128]T.Id = @splat(0),
    views: ?*Context = null,
    pending: [128]T.Effects.Id = undefined,
    pending_count: usize = 0,
    foreign_views: bool = false,
    left_rows: T.List = .{},
    instance_rows: T.List = .{},
    scheme_row_witnesses: [128]?RowWitness = @splat(null),
    row_search_depth: usize = 0,
    projection_resolver: ?PrincipalProjectionResolver = null,
    projection_depth: usize = 0,
    certificate_pairs: ?*CertificatePairs = null,
    version_pairs: []const VersionPair = &.{},
    pub const VersionPair = struct { left: T.Node, right: T.Node };
    const RowWitness = struct { row: T.Effects.Id, excluded: std.bit_set.Static(256) = .empty };
    pub const CertificatePairs = struct {
        left: T.List,
        right: T.List,
        seen_left: std.bit_set.Static(4096) = .empty,
        seen_right: std.bit_set.Static(4096) = .empty,
    };
    fn certificateRow(self: *Principal, left: T.Effects.Id, right: T.Effects.Id) Error!void {
        const pairs = self.certificate_pairs orelse return;
        const a = self.left.row(left);
        const b = self.right.row(right);
        var x: ?usize = null;
        var y: ?usize = null;
        for (self.left.list(pairs.left), 0..) |variable, ordinal| {
            try require(self.remaining.* != 0);
            self.remaining.* -= 1;
            if (a.tail == .variable and a.tail.variable == variable) x = ordinal;
        }
        for (self.right.list(pairs.right), 0..) |variable, ordinal| {
            try require(self.remaining.* != 0);
            self.remaining.* -= 1;
            if (b.tail == .variable and b.tail.variable == variable) y = ordinal;
        }
        try require((x == null) == (y == null));
        if (x) |ordinal| {
            try require(ordinal < 4096 and y.? < 4096);
            pairs.seen_left.set(ordinal);
            pairs.seen_right.set(y.?);
        }
    }
    /// Imported certificates must occur on corresponding exact scheme rows.
    /// This also checks unused imported slots, independently of call discovery.
    pub fn certifiedScheme(self: *Principal, expected: T.Scheme, actual: T.Scheme, left_goals: anytype, right_goals: anytype) Error!void {
        try require(expected.closed_rows.len == actual.closed_rows.len and expected.closed_rows.len <= 4096);
        var pairs: CertificatePairs = .{ .left = expected.closed_rows, .right = actual.closed_rows };
        self.certificate_pairs = &pairs;
        defer self.certificate_pairs = null;
        try self.schemeGoals(expected, actual, left_goals, right_goals);
        // Internal body tails may be absent from the exported endpoints.
        // Their copied slots are alpha names; observable certificates must
        // correspond, and neither side may add or erase an internal slot.
        try require(pairs.seen_left.count() == pairs.seen_right.count());
    }
    pub fn substituted(self: *Principal, formals: T.List, replacements: []const T.Id, expected: T.Id, actual: T.Id) Error!void {
        try require(formals.len == replacements.len and formals.len <= self.witnesses.len);
        self.instance = formals;
        @memcpy(self.witnesses[0..replacements.len], replacements);
        defer self.instance = .{};
        try self.validate(expected, actual);
    }
    /// The first replacements live in the right graph. Apply the second,
    /// independently owned formal map there before comparing an endpoint.
    pub fn composed(self: *Principal, formals: T.List, replacements: []const T.Id, secondary: T.List, secondary_replacements: []const T.Id, expected: T.Id, actual: T.Id) Error!void {
        try require(secondary.len == secondary_replacements.len and secondary.len <= self.secondary_witnesses.len);
        self.secondary = secondary;
        @memcpy(self.secondary_witnesses[0..secondary_replacements.len], secondary_replacements);
        defer self.secondary = .{};
        try self.substituted(formals, replacements, expected, actual);
    }
    /// Publication compares schemes by a bijection of their owned variables,
    /// rather than the one-way instantiation used at an executable call.
    pub fn schemeGoals(self: *Principal, expected: T.Scheme, actual: T.Scheme, left_goals: anytype, right_goals: anytype) Error!void {
        try require(left_goals.len == right_goals.len and expected.row_variables.len == actual.row_variables.len);
        const left_owner = self.left.node(expected.root);
        const right_owner = self.right.node(actual.root);
        const paired_scope = left_owner.tag == .forall and right_owner.tag == .forall;
        try require(left_owner.tag == right_owner.tag);
        if (paired_scope) {
            try self.validate(expected.root, actual.root);
            try require(left_owner.c == right_owner.c and self.formal_count < self.formals.len);
            self.formals[self.formal_count] = .{ .left = .{ .start = left_owner.b, .len = left_owner.c }, .right = .{ .start = right_owner.b, .len = right_owner.c } };
            self.formal_count += 1;
        } else {
            try require(expected.variables.len == actual.variables.len);
            try self.instantiateScheme(expected, actual.root);
        }
        defer {
            if (paired_scope) self.formal_count -= 1;
        }
        try require(expected.variables.len <= self.witnesses.len and expected.row_variables.len <= self.scheme_row_witnesses.len);
        self.instance = expected.variables;
        self.instance_rows = expected.row_variables;
        defer self.instance = .{};
        defer self.instance_rows = .{};
        if (paired_scope) self.instance = .{};
        for (left_goals, right_goals) |left, right| {
            try require(left.kind == right.kind and left.name == right.name and left.operator == right.operator and left.identity.unit == right.identity.unit and left.identity.decl == right.identity.decl);
            inline for (.{ "ty", "other", "result", "signature" }) |field| {
                const x = @field(left, field);
                const y = @field(right, field);
                if (x == 0 or y == 0) try require(x == y) else try self.validate(x, y);
            }
        }
        if (paired_scope) return;
        var variables: std.bit_set.Static(128) = .empty;
        for (self.witnesses[0..expected.variables.len]) |witness| {
            if (witness == 0) continue; // An unused phantom has no observable endpoint.
            var found = false;
            for (self.right.list(actual.variables), 0..) |variable, ordinal| {
                if (variable != witness) continue;
                try require(!variables.isSet(ordinal));
                variables.set(ordinal);
                found = true;
                break;
            }
            try require(found);
        }
        var rows_: std.bit_set.Static(128) = .empty;
        for (self.scheme_row_witnesses[0..expected.row_variables.len]) |witness| {
            const replacement = witness orelse continue;
            const row = self.right.row(replacement.row);
            try require(row.tail == .variable and replacement.excluded.count() == row.labels.len);
            var found = false;
            for (self.right.list(actual.row_variables), 0..) |variable, ordinal| {
                if (variable != row.tail.variable) continue;
                try require(!rows_.isSet(ordinal));
                rows_.set(ordinal);
                found = true;
                break;
            }
            try require(found);
        }
    }
    pub fn rows(self: *Principal, left: T.Effects.Id, right: T.Effects.Id) Error!void {
        try self.matchRow(left, right, 0);
    }
    pub fn instantiateScheme(self: *Principal, scheme: T.Scheme, actual: T.Id) Error!void {
        try require(scheme.variables.len <= self.witnesses.len and scheme.row_variables.len <= self.scheme_row_witnesses.len);
        self.instance = scheme.variables;
        self.instance_rows = scheme.row_variables;
        self.witnesses = @splat(0);
        self.scheme_row_witnesses = @splat(null);
        defer self.instance = .{};
        defer self.instance_rows = .{};
        var endpoint = actual;
        const quantified_actual = self.right.node(actual).tag == .forall;
        if (quantified_actual) {
            const views = self.views orelse return error.InvalidArtifact;
            try require(views.types == self.right);
            try views.enter(actual);
            endpoint = self.right.node(actual).a;
        }
        defer if (quantified_actual) self.views.?.leave();
        try self.validate(scheme.root, endpoint);
    }
    pub fn instantiate(self: *Principal, owner: T.Id, actual: T.Id) Error!void {
        try require(self.left.quantifierGoals(owner).len == 0);
        return self.instantiateTypes(owner, actual);
    }
    /// Type correspondence only. Qualified callers must independently discharge
    /// every owned predicate before admitting the executable use.
    pub fn instantiateTypes(self: *Principal, owner: T.Id, actual: T.Id) Error!void {
        try require(owner < self.left.nodes.len);
        const quantifier = self.left.node(owner);
        try require(quantifier.tag == .forall and quantifier.c != 0 and quantifier.c <= self.witnesses.len);
        self.instance = .{ .start = quantifier.b, .len = quantifier.c };
        self.witnesses = @splat(0);
        self.row_witnesses = @splat(null);
        defer self.instance = .{};
        try self.validate(quantifier.a, actual);
    }
    pub fn validate(self: *Principal, left: T.Id, right: T.Id) Error!void {
        self.pending_count = 0;
        try self.match(left, right, 0);
        if (self.views) |views| for (self.pending[0..self.pending_count]) |row| {
            try views.closed_rows.set(row);
            if (views.types.row(row).labels.len == 0) try views.pure_rows.set(row);
        };
    }
    fn rowPure(self: *const Principal, types: *const core.Types, row: T.Effects.Id) bool {
        if (types == self.left and row < types.effects.rows.len) {
            const value = types.row(row);
            if (value.labels.len == 0 and value.tail == .variable and @import("std").mem.findScalar(u32, types.list(self.left_rows), value.tail.variable) != null) return true;
        }
        if (self.views) |views| if (views.types == types) return views.isPure(row);
        return pure(types, row);
    }
    fn rowForeign(self: *const Principal, types: *const core.Types, id: T.Effects.Id) bool {
        if (foreign(types, id)) return true;
        if (self.views) |views| if (views.types == types and views.isForeign(id)) return true;
        if (types != self.left or id >= types.effects.rows.len) return false;
        const row = types.row(id);
        if (row.tail != .variable or row.labels.len == 0 or @import("std").mem.findScalar(u32, types.list(self.left_rows), row.tail.variable) == null) return false;
        for (types.rowLabels(id)) |label| if (label != T.foreign_operation) return false;
        return true;
    }
    fn operation(self: *Principal, left: T.Effects.Label, right: T.Effects.Label, depth: usize) Error!void {
        try require(self.remaining.* != 0 and depth < 128);
        self.remaining.* -= 1;
        try require(left != 0 and right != 0 and left < self.left.operations.len and right < self.right.operations.len);
        const a = self.left.operation(left);
        const b = self.right.operation(right);
        try require(std.meta.eql(a.identity, b.identity) and a.instance.unit == b.instance.unit and a.arguments.len == b.arguments.len);
        if (a.instance.unit == 0 and a.instance.decl != 0 and b.instance.decl != 0) try self.match(a.instance.decl, b.instance.decl, depth + 1) else try require(a.instance.decl == b.instance.decl);
        for (try span(self.left, a.arguments), try span(self.right, b.arguments)) |x, y| try self.match(x, y, depth + 1);
    }
    fn closedRow(self: *Principal, types: *const core.Types, id: T.Effects.Id) bool {
        if (id >= types.effects.rows.len) return false;
        const row = types.row(id);
        if (row.tail == .closed) return true;
        if (self.views) |views| if (views.types == types and views.closed_rows.contains(id)) return true;
        if (types == self.left and row.tail == .variable) return std.mem.findScalar(u32, types.list(self.left_rows), row.tail.variable) != null;
        return false;
    }
    fn structuredRow(self: *Principal, left: T.Effects.Id, right: T.Effects.Id, left_excluded: std.bit_set.Static(256), right_excluded: std.bit_set.Static(256), subset: bool, depth: usize) Error!void {
        try require(depth < 128 and self.remaining.* != 0 and left < self.left.effects.rows.len and right < self.right.effects.rows.len);
        self.remaining.* -= 1;
        const xs = self.left.rowLabels(left);
        const ys = self.right.rowLabels(right);
        try require(xs.len <= 256 and ys.len <= 256);
        try self.rowLabels(left, right, left_excluded, right_excluded, subset, 0, depth);
    }
    fn rowLabels(self: *Principal, left: T.Effects.Id, right: T.Effects.Id, left_excluded: std.bit_set.Static(256), used: std.bit_set.Static(256), subset: bool, start: usize, depth: usize) Error!void {
        try require(self.row_search_depth < 257 and self.remaining.* != 0);
        self.remaining.* -= 1;
        self.row_search_depth += 1;
        defer self.row_search_depth -= 1;
        const xs = self.left.rowLabels(left);
        const ys = self.right.rowLabels(right);
        var ordinal = start;
        while (ordinal < xs.len and left_excluded.isSet(ordinal)) ordinal += 1;
        if (ordinal == xs.len) return self.rowTail(left, right, used, subset, depth);
        for (ys, 0..) |candidate, index| {
            try require(self.remaining.* != 0);
            self.remaining.* -= 1;
            if (used.isSet(index)) continue;
            const solver = if (self.views) |views| views.solver else null;
            const mark = if (solver) |owner| owner.store.mark() else null;
            const saved = self.witnesses;
            const saved_rows = self.row_witnesses;
            const saved_scheme_rows = self.scheme_row_witnesses;
            const pending = self.pending_count;
            self.operation(xs[ordinal], candidate, depth + 1) catch {
                if (solver) |owner| owner.rollback(mark.?);
                self.witnesses = saved;
                self.row_witnesses = saved_rows;
                self.scheme_row_witnesses = saved_scheme_rows;
                self.pending_count = pending;
                try require(self.remaining.* != 0);
                continue;
            };
            var next = used;
            next.set(index);
            self.rowLabels(left, right, left_excluded, next, subset, ordinal + 1, depth) catch {
                if (solver) |owner| owner.rollback(mark.?);
                self.witnesses = saved;
                self.row_witnesses = saved_rows;
                self.scheme_row_witnesses = saved_scheme_rows;
                self.pending_count = pending;
                try require(self.remaining.* != 0);
                continue;
            };
            return;
        }
        return error.InvalidArtifact;
    }
    fn rowTail(self: *Principal, left: T.Effects.Id, right: T.Effects.Id, used: std.bit_set.Static(256), subset: bool, depth: usize) Error!void {
        const a = self.left.row(left);
        const b = self.right.row(right);
        const ys = self.right.rowLabels(right);
        if (a.tail == .variable and self.instance_rows.len != 0 and !subset) {
            for (try span(self.left, self.instance_rows), 0..) |variable, ordinal| {
                if (variable != a.tail.variable) continue;
                if (self.scheme_row_witnesses[ordinal]) |prior| {
                    var proof: Principal = .{ .left = self.right, .right = self.right, .remaining = self.remaining, .views = self.views };
                    try proof.structuredRow(prior.row, right, prior.excluded, used, false, depth + 1);
                    try require(self.pending_count + proof.pending_count <= self.pending.len);
                    @memcpy(self.pending[self.pending_count..][0..proof.pending_count], proof.pending[0..proof.pending_count]);
                    self.pending_count += proof.pending_count;
                } else self.scheme_row_witnesses[ordinal] = .{ .row = right, .excluded = used };
                return;
            }
        }
        if (a.tail == .formal and self.instance.len != 0 and !subset) {
            for (try span(self.left, self.instance), 0..) |binder, ordinal| {
                if (binder != a.tail.formal) continue;
                try require(self.left.node(binder).tag == .bound and self.left.node(binder).b == 1);
                if (self.row_witnesses[ordinal]) |prior| {
                    var proof: Principal = .{ .left = self.right, .right = self.right, .remaining = self.remaining, .views = self.views };
                    try proof.structuredRow(prior.row, right, prior.excluded, used, false, depth + 1);
                    try require(self.pending_count + proof.pending_count <= self.pending.len);
                    @memcpy(self.pending[self.pending_count..][0..proof.pending_count], proof.pending[0..proof.pending_count]);
                    self.pending_count += proof.pending_count;
                } else self.row_witnesses[ordinal] = .{ .row = right, .excluded = used };
                return;
            }
        }
        if (a.tail == .formal) {
            try require(b.tail == .formal);
            try self.match(a.tail.formal, b.tail.formal, depth + 1);
        } else if (!subset or a.tail != .closed) {
            if (!(self.closedRow(self.left, left) and self.closedRow(self.right, right)) and !std.meta.eql(a.tail, b.tail)) {
                const views = self.views orelse return error.InvalidArtifact;
                try require(!subset and self.closedRow(self.left, left) and views.types == self.right and b.tail == .variable);
                try require(self.pending_count < self.pending.len);
                self.pending[self.pending_count] = right;
                self.pending_count += 1;
            }
        }
        if (!subset) for (ys, 0..) |_, index| try require(used.isSet(index));
    }
    pub fn subsetRow(self: *Principal, actual: T.Effects.Id, declared: T.Effects.Id) Error!void {
        return self.structuredRow(actual, declared, .empty, .empty, true, 0);
    }
    /// Exclusions are exact operation occurrences owned by active handlers.
    /// Tail matching remains structural; a handler never manufactures a tail.
    pub fn handledRow(self: *Principal, actual: T.Effects.Id, declared: T.Effects.Id, excluded: std.bit_set.Static(256), subset: bool) Error!void {
        return self.structuredRow(actual, declared, excluded, .empty, subset, 0);
    }
    fn matchRow(self: *Principal, left: T.Effects.Id, right: T.Effects.Id, depth: usize) Error!void {
        if (self.views) |views| if (views.solver) |solver| {
            if (self.left == views.types and self.right == views.types) {
                const l = solver.resolveRow(left) catch |err| return solver.readerError(err);
                const r = solver.resolveRow(right) catch |err| return solver.readerError(err);
                if (l != left or r != right) return self.matchRow(l, r, depth + 1);
                if (solver.store.effects.node(l).tail == .variable or solver.store.effects.node(r).tail == .variable) {
                    solver.rows(l, r) catch |err| return solver.readerError(err);
                    return;
                }
            }
        };
        try self.certificateRow(left, right);
        if (left < self.left.effects.rows.len and right < self.right.effects.rows.len) {
            const a = self.left.row(left);
            const b = self.right.row(right);
            if (self.foreign_views and self.rowPure(self.left, left) and b.tail == .formal) {
                const views = self.views orelse return error.InvalidArtifact;
                try require(views.types == self.right);
                const leaf = self.right.node(b.tail.formal);
                if (leaf.tag == .rigid) {
                    try require(views.solver != null and views.solver.?.ownsRigid(leaf) and leaf.c == 1);
                } else try require(views.ownsFormal(b.tail.formal));
                try views.validateRow(right, depth + 1);
                return;
            }
            var generic_row = false;
            if (self.views) |views| if (self.left == self.right and views.types == self.left) {
                generic_row = try views.genericRow(left, depth + 1);
            };
            if (generic_row or a.tail == .formal or b.tail == .formal or (a.tail == .variable and self.instance_rows.len != 0) or (a.labels.len != 0 and (b.tail != .closed or !self.rowForeign(self.left, left)))) {
                var subset = self.foreign_views and self.closedRow(self.left, left);
                if (subset and self.rowForeign(self.left, left) and b.tail == .variable) {
                    const views = self.views orelse return error.InvalidArtifact;
                    try require(views.types == self.right and b.tail.variable < self.right.effects.variable_count);
                    // An exact host-effect read can add an inference tail.
                    // Its whole endpoint proof closes only that matched view;
                    // wider or generic ambient rows retain ordinary covariance.
                    if (!try views.ownsRow(b.tail.variable)) {
                        var exact = a.labels.len == b.labels.len;
                        for (self.right.rowLabels(right)) |label| {
                            try require(self.remaining.* != 0);
                            self.remaining.* -= 1;
                            if (label != T.foreign_operation) exact = false;
                        }
                        if (exact) subset = false;
                    }
                }
                return self.structuredRow(left, right, .empty, .empty, subset, depth + 1);
            }
        }
        if (self.rowForeign(self.left, left)) {
            try require(self.rowForeign(self.right, right) and self.left.row(left).labels.len == self.right.row(right).labels.len);
            return;
        }
        try require(self.rowPure(self.left, left));
        if (self.foreign_views and self.rowForeign(self.right, right)) return;
        if (self.rowPure(self.right, right)) return;
        if (self.foreign_views and self.right.row(right).labels.len != 0) {
            const views = self.views orelse return error.InvalidArtifact;
            try require(views.types == self.right);
            // A pure producer may retain the selected use's conservative
            // effect superset. Inputs disable this covariant source view.
            try views.validateRow(right, depth + 1);
            return;
        }
        const views = self.views orelse return error.InvalidArtifact;
        try require(views.types == self.right and right < self.right.effects.rows.len);
        const actual = self.right.row(right);
        // Covariant source reads may add an empty inference tail. Only an
        // independently matched pure owner recipe discharges that view.
        try require(actual.labels.len == 0 and actual.tail == .variable and actual.tail.variable < self.right.effects.variable_count);
        for (self.pending[0..self.pending_count]) |pending| {
            try require(self.remaining.* != 0);
            self.remaining.* -= 1;
            if (pending == right) return;
        }
        try require(self.pending_count < self.pending.len);
        self.pending[self.pending_count] = right;
        self.pending_count += 1;
    }
    fn match(self: *Principal, left: T.Id, right: T.Id, depth: usize) Error!void {
        if (depth >= 128 or self.remaining.* == 0) {
            self.remaining.* = 0;
            return error.InvalidArtifact;
        }
        self.remaining.* -= 1;
        try require(left < self.left.nodes.len and right < self.right.nodes.len);
        if (self.views) |views| if (views.solver) |solver| {
            if (self.left == views.types and self.right == views.types) {
                const l = solver.store.head(left, 0);
                const r = solver.store.head(right, 0);
                if (l != left or r != right) return self.match(l, r, depth + 1);
                if (solver.store.node(l).tag == .variable or solver.store.node(r).tag == .variable) {
                    solver.unify(l, r) catch |err| return solver.readerError(err);
                    return;
                }
            }
        };
        const a = self.left.node(left);
        const b = self.right.node(right);
        if ((a.tag == .variable or (a.tag == .bound and a.c == 0)) and self.instance.len != 0) {
            for (try span(self.left, self.instance), 0..) |binder, ordinal| {
                if (binder != left) continue;
                if (a.tag == .bound) {
                    if (a.b == 0) {
                        var work: @import("usage_check.zig").Work = .{ .remaining = self.remaining.* };
                        defer self.remaining.* = work.remaining;
                        try require(!(@import("usage_check.zig").containsNominalWork(self.right, &[_]core.Nominal{}, right, &work) catch return error.InvalidArtifact));
                    } else try require(a.b == 2 and b.tag == .bound and b.b == 2);
                }
                if (self.witnesses[ordinal] == 0) {
                    self.witnesses[ordinal] = right;
                    return;
                }
                var proof: Principal = .{ .left = self.right, .right = self.right, .remaining = self.remaining, .views = self.views, .instance = self.secondary, .witnesses = self.secondary_witnesses };
                try proof.match(self.witnesses[ordinal], right, depth + 1);
                try require(self.pending_count + proof.pending_count <= self.pending.len);
                @memcpy(self.pending[self.pending_count..][0..proof.pending_count], proof.pending[0..proof.pending_count]);
                self.pending_count += proof.pending_count;
                return;
            }
        }
        if (a.tag == .projection and b.tag != .projection) {
            const resolver = self.projection_resolver orelse return error.InvalidArtifact;
            try require(self.projection_depth < 128);
            self.projection_depth += 1;
            defer self.projection_depth -= 1;
            return resolver.validate(resolver.context, self, left, right);
        }
        try require(a.tag == b.tag);
        switch (a.tag) {
            .unit, .boolean, .u32, .f32, .never, .erased_proof => {},
            // Exact mapped catalog formals remain graph-owned; lexical
            // admission still rejects free variables in executable types.
            .variable => try require(self.left == self.right and left == right),
            .rigid => try require(self.left == self.right and a.a == b.a and a.b == b.b and a.c == b.c and self.views != null and self.views.?.solver != null and self.views.?.solver.?.ownsRigid(a)),
            .bound => {
                try require(a.b == b.b and a.b <= 2);
                if (a.c == 0 and b.c == 0) {
                    for (self.formals[0..self.formal_count]) |formal| {
                        const l = try span(self.left, formal.left);
                        const r = try span(self.right, formal.right);
                        if (a.a < l.len and b.a < r.len and l[a.a] == left and r[b.a] == right) {
                            try require(a.a == b.a);
                            return;
                        }
                    }
                    const views = self.views orelse return error.InvalidArtifact;
                    try require(self.left == self.right and left == right and views.ownsFormal(left));
                } else try require(self.left == self.right and left == right and a.c != 0 and b.c != 0);
            },
            .forall, .existential => {
                try require(a.c == b.c and self.formal_count < self.formals.len);
                const left_binders = try span(self.left, .{ .start = a.b, .len = a.c });
                const right_binders = try span(self.right, .{ .start = b.b, .len = b.c });
                for (left_binders, right_binders) |x, y| try require(self.left.node(x).b == self.right.node(y).b);
                self.formals[self.formal_count] = .{ .left = .{ .start = a.b, .len = a.c }, .right = .{ .start = b.b, .len = b.c } };
                self.formal_count += 1;
                defer self.formal_count -= 1;
                const left_goals = self.left.quantifierGoals(left);
                const right_goals = self.right.quantifierGoals(right);
                try require(left_goals.len == right_goals.len);
                for (left_goals, right_goals) |x, y| {
                    try require(@import("quantifier_goals.zig").sameHead(x, y));
                    inline for (.{ "ty", "other", "result", "signature" }) |field| {
                        try require((@field(x, field) == 0) == (@field(y, field) == 0));
                        if (@field(x, field) != 0) try self.match(@field(x, field), @field(y, field), depth + 1);
                    }
                }
                try self.match(a.a, b.a, depth + 1);
            },
            .function => {
                try self.matchRow(a.c, b.c, depth + 1);
                const outer = self.foreign_views;
                self.foreign_views = false;
                try self.match(a.a, b.a, depth + 1);
                self.foreign_views = outer;
                try self.match(a.b, b.b, depth + 1);
            },
            .usage => {
                try require(a.b == b.b and (a.c == 0) == (b.c == 0));
                if (a.c != 0) try self.match(a.c, b.c, depth + 1);
                try self.match(a.a, b.a, depth + 1);
            },
            .scoped => {
                try require(a.b == b.b and (a.b == 0) == (b.b == 0));
                if (a.b == 0) try self.match(a.c, b.c, depth + 1) else try require(a.c == b.c);
                try self.match(a.a, b.a, depth + 1);
            },
            .instance_version => {
                if (a.a == b.a and a.b == b.b and a.c == b.c) return;
                for (self.version_pairs) |pair| {
                    try require(self.remaining.* != 0);
                    self.remaining.* -= 1;
                    if (a.a == pair.left.a and a.b == pair.left.b and a.c == pair.left.c and b.a == pair.right.a and b.b == pair.right.b and b.c == pair.right.c) return;
                }
                return error.InvalidArtifact;
            },
            .instance_selection => {
                try require(a.a == b.a and a.b == b.b);
                const left_choices = self.left.nominalArguments(a);
                const right_choices = self.right.nominalArguments(b);
                try require(left_choices.len == right_choices.len);
                for (left_choices, right_choices) |x, y| try self.match(x, y, depth + 1);
            },
            .array, .list, .cursor => try self.match(a.a, b.a, depth + 1),
            .demand, .provider => {
                try require(a.b == 0 and b.b == 0);
                try self.matchRow(a.c, b.c, depth + 1);
                try self.match(a.a, b.a, depth + 1);
            },
            .resolver => try self.match(a.a, b.a, depth + 1),
            .type_constructor => try require(a.a == b.a and a.b == b.b and a.c == 0 and b.c == 0),
            .state_provider => {
                try self.match(a.a, b.a, depth + 1);
                try self.match(a.b, b.b, depth + 1);
                try self.match(a.c, b.c, depth + 1);
            },
            .product => {
                try require(a.b == b.b);
                for (try span(self.left, .{ .start = a.a, .len = a.b }), try span(self.right, .{ .start = b.a, .len = b.b })) |x, y| try self.match(x, y, depth + 1);
            },
            .record => {
                try require(a.b == b.b and a.b <= 0x7fff_ffff);
                _ = try span(self.left, .{ .start = a.a, .len = a.b * 2 });
                _ = try span(self.right, .{ .start = b.a, .len = b.b * 2 });
                for (0..a.b) |index| {
                    const field = self.left.recordField(a, index);
                    var found = false;
                    for (0..b.b) |other| {
                        try require(self.remaining.* != 0);
                        self.remaining.* -= 1;
                        const candidate = self.right.recordField(b, other);
                        if (field.name != candidate.name) continue;
                        try self.match(field.ty, candidate.ty, depth + 1);
                        found = true;
                        break;
                    }
                    try require(found);
                }
            },
            .nominal, .projection => {
                try require(a.a == b.a and a.b == b.b and a.c < self.left.extra.len and b.c < self.right.extra.len);
                if (a.tag == .projection) try require(try projectionMember(self.left, a) == try projectionMember(self.right, b));
                const l = try span(self.left, .{ .start = a.c + 1, .len = self.left.extra[a.c] });
                const r = try span(self.right, .{ .start = b.c + 1, .len = self.right.extra[b.c] });
                try require(l.len == r.len);
                for (l, r) |x, y| try self.match(x, y, depth + 1);
            },
            else => return error.InvalidArtifact,
        }
    }
};

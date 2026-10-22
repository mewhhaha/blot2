//! Admission for owned staged Core. Bounds and structural cycles must already
//! be checked; this pass proves each compiler-owned shape and intrinsic edge.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const staging = @import("typed_staging.zig");
const cross = @import("staging_type_match.zig");
const Error = error{InvalidArtifact};
fn require(value: bool) Error!void {
    if (!value) return error.InvalidArtifact;
}
pub fn authorityFree(m: *const core.Module, id: T.Id) Error!bool {
    var remaining: usize = 4096;
    return authorityDepth(m, id, 0, &remaining);
}
fn authorityRow(m: *const core.Module, row: T.Effects.Id, depth: usize, remaining: *usize) Error!bool {
    const labels = m.types.effects.node(row).labels;
    for (m.types.effects.labels[labels.start..][0..labels.len]) |label| {
        const operation = m.types.operations[label];
        if (operation.instance.decl != 0) return false;
        for (m.types.list(operation.arguments)) |argument| if (!try authorityDepth(m, argument, depth + 1, remaining)) return false;
    }
    return true;
}
fn authorityDepth(m: *const core.Module, id: T.Id, depth: usize, remaining: *usize) Error!bool {
    try require(depth < 128 and remaining.* != 0);
    remaining.* -= 1;
    const n = m.types.node(id);
    switch (n.tag) {
        .scoped, .instance_version, .bound, .rigid, .forall, .existential => return false,
        .usage => {
            if (n.b == @backingInt(T.UsageKind.borrow) or n.b == @backingInt(T.UsageKind.borrow_mut)) return false;
            return authorityDepth(m, n.a, depth + 1, remaining);
        },
        .function => return try authorityDepth(m, n.a, depth + 1, remaining) and try authorityDepth(m, n.b, depth + 1, remaining) and try authorityRow(m, n.c, depth + 1, remaining),
        .demand, .provider => return try authorityDepth(m, n.a, depth + 1, remaining) and try authorityRow(m, n.c, depth + 1, remaining),
        .state_provider => return try authorityDepth(m, n.a, depth + 1, remaining) and try authorityDepth(m, n.b, depth + 1, remaining) and try authorityDepth(m, n.c, depth + 1, remaining),
        .nominal, .projection, .instance_selection => for (m.types.nominalArguments(n)) |child| {
            if (!try authorityDepth(m, child, depth + 1, remaining)) return false;
        },
        .record => for (0..n.b) |i| {
            if (!try authorityDepth(m, m.types.recordField(n, i).ty, depth + 1, remaining)) return false;
        },
        .product => for (m.types.list(.{ .start = n.a, .len = n.b })) |child| {
            if (!try authorityDepth(m, child, depth + 1, remaining)) return false;
        },
        .array, .list, .cursor, .resolver => return authorityDepth(m, n.a, depth + 1, remaining),
        else => {},
    }
    return true;
}

fn equal(m: *const core.Module, left: T.Id, right: T.Id, depth: usize, remaining: *usize) Error!bool {
    return equalWithRows(m, left, right, .{}, depth, remaining);
}
fn sameRow(m: *const core.Module, left: T.Effects.Id, right: T.Effects.Id, closed_rows: T.List) bool {
    return sameOwnedRow(m, left, right, closed_rows, closed_rows);
}
fn sameOwnedRow(m: *const core.Module, left: T.Effects.Id, right: T.Effects.Id, left_rows: T.List, right_rows: T.List) bool {
    if (left == right) return true;
    const a = m.types.effects.node(left);
    const b = m.types.effects.node(right);
    if (!std.mem.eql(u32, m.types.effects.labels[a.labels.start..][0..a.labels.len], m.types.effects.labels[b.labels.start..][0..b.labels.len])) return false;
    var first = a.tail;
    var second = b.tail;
    if (first == .variable and std.mem.findScalar(u32, m.types.list(left_rows), first.variable) != null) first = .closed;
    if (second == .variable and std.mem.findScalar(u32, m.types.list(right_rows), second.variable) != null) second = .closed;
    return std.meta.eql(first, second);
}
fn equalWithRows(m: *const core.Module, left: T.Id, right: T.Id, closed_rows: T.List, depth: usize, remaining: *usize) Error!bool {
    return equalOwnedRows(m, left, right, closed_rows, closed_rows, depth, remaining);
}
fn equalOwnedRows(m: *const core.Module, left: T.Id, right: T.Id, left_rows: T.List, right_rows: T.List, depth: usize, remaining: *usize) Error!bool {
    try require(depth < 128 and remaining.* != 0);
    remaining.* -= 1;
    if (left == right) return true;
    const a = m.types.node(left);
    const b = m.types.node(right);
    if (a.tag != b.tag) return false;
    switch (a.tag) {
        .variable => return false,
        .product => {
            if (a.b != b.b) return false;
            for (m.types.list(.{ .start = a.a, .len = a.b }), m.types.list(.{ .start = b.a, .len = b.b })) |x, y| if (!try equalOwnedRows(m, x, y, left_rows, right_rows, depth + 1, remaining)) return false;
            return true;
        },
        .record => {
            if (a.b != b.b) return false;
            for (0..a.b) |i| {
                const x = m.types.recordField(a, i);
                const y = m.types.recordField(b, i);
                if (x.name != y.name or !try equalOwnedRows(m, x.ty, y.ty, left_rows, right_rows, depth + 1, remaining)) return false;
            }
            return true;
        },
        .nominal => {
            if (a.a != b.a or a.b != b.b) return false;
            const xs = m.types.nominalArguments(a);
            const ys = m.types.nominalArguments(b);
            if (xs.len != ys.len) return false;
            for (xs, ys) |x, y| if (!try equalOwnedRows(m, x, y, left_rows, right_rows, depth + 1, remaining)) return false;
            return true;
        },
        .function => return try equalOwnedRows(m, a.a, b.a, left_rows, right_rows, depth + 1, remaining) and try equalOwnedRows(m, a.b, b.b, left_rows, right_rows, depth + 1, remaining) and sameOwnedRow(m, a.c, b.c, left_rows, right_rows),
        .existential => {
            var proof: @import("package_contracts.zig").Principal = .{ .left = &m.types, .right = &m.types, .remaining = remaining };
            proof.validate(left, right) catch return false;
            return true;
        },
        .state_provider => return try equalOwnedRows(m, a.a, b.a, left_rows, right_rows, depth + 1, remaining) and try equalOwnedRows(m, a.b, b.b, left_rows, right_rows, depth + 1, remaining) and try equalOwnedRows(m, a.c, b.c, left_rows, right_rows, depth + 1, remaining),
        .usage, .array, .list, .cursor, .demand, .provider, .resolver => return a.b == b.b and a.c == b.c and try equalOwnedRows(m, a.a, b.a, left_rows, right_rows, depth + 1, remaining),
        else => return a.a == b.a and a.b == b.b and a.c == b.c,
    }
}
fn result(m: *const core.Module, expected: T.Id, actual: T.Id, remaining: *usize) Error!void {
    // Never inhabits any declared result, retaining a delayed quoted trap.
    try require(actual == T.never or try equal(m, expected, actual, 0, remaining));
}
fn callable(m: *const core.Module, raw: T.Id, remaining: *usize) Error!T.Node {
    var current = raw;
    for (0..128) |_| {
        try require(remaining.* != 0);
        remaining.* -= 1;
        const node_ = m.types.node(current);
        if (node_.tag != .usage) {
            try require(node_.tag == .function);
            return node_;
        }
        current = node_.a;
    }
    return error.InvalidArtifact;
}
fn nominalOwner(m: *const core.Module, target: T.Node, remaining: *usize) Error!u32 {
    try require(target.tag == .nominal);
    var owner: ?u32 = null;
    for (m.nominals, 0..) |family, index| {
        try require(remaining.* != 0);
        remaining.* -= 1;
        if (family.identity.unit != target.a or family.identity.decl != target.b) continue;
        try require(owner == null and family.constructors.len != 0);
        // Sealed producer bodies retain their own representation rights. The
        // consumer's mirrored private/opaque catalog grants no such access.
        if (family.private or family.is_opaque) try require(family.identity.unit == 0 or family.identity.unit == m.unit);
        owner = @intCast(index);
    }
    return owner orelse error.InvalidArtifact;
}
// Named future bodies reconstruct their lexical, type and effect owners.
// Scheme variables are substituted per call; a selected arrow cannot authorize
// captures, effects or lexical identities by describing its own result.
const Named = struct {
    workspace: ?*@import("scheme_equations.zig").Workspace = null,
    m: *const core.Module,
    units: []const *const core.Module = &.{},
    remaining: *usize,
    variables: []const T.Id = &.{},
    current_scheme: ?T.Scheme = null,
    row_variables: T.List = .{},
    data_rows: T.List = .{},
    row_owners: ?*const RowOwner = null,
    parameters: []const core.Parameter = &.{},
    locals: ?*const Locals = null,
    loop_owner: ?*LoopOwner = null,
    scope_owner: ?*const ScopeOwner = null,
    loan_owner: ?*const LoanOwner = null,
    active_calls: ?*const CallOwner = null,
    ambient: ?T.Effects.Row = null,
    decision_owner: ?*const DecisionOwner = null,
    resolver_callback: core.Id = 0,
    const DecisionOwner = struct { callback: core.Id, ty: T.Id, breaks: *bool };
    const Locals = struct { bindings: []const core.BindingId = &.{}, parameters: []const core.Parameter = &.{}, parent: ?*const Locals };
    const LoopOwner = struct { node: core.Id, parent: ?*LoopOwner, exits: bool = false };
    const ScopeOwner = struct { identity: T.NominalIdentity, parent: ?*const ScopeOwner, task_view: T.Id = 0 };
    const LoanOwner = struct { region: T.Id, parent: ?*const LoanOwner };
    const CallOwner = struct { module: *const core.Module, binding: core.BindingId, parent: ?*const CallOwner };
    fn declaredBody(self: *Named, body: *const core.Body, parameters: []const core.Parameter, depth: usize) Error!void {
        var active = self.active_calls;
        while (active) |owner| : (active = owner.parent) {
            try self.step(depth);
            if (owner.module == self.m and owner.binding == body.binding) return;
        }
        const prior_parameters = self.parameters;
        self.parameters = parameters;
        defer self.parameters = prior_parameters;
        const prior_scheme = self.current_scheme;
        self.current_scheme = body.scheme;
        defer self.current_scheme = prior_scheme;
        const prior_ambient = self.ambient;
        defer self.ambient = prior_ambient;
        var signature = self.m.bindings[body.binding].ty;
        self.ambient = null;
        for (parameters) |_| {
            const arrow = try callable(self.m, signature, self.remaining);
            self.ambient = self.m.types.row(arrow.c);
            signature = arrow.b;
        }
        const prior_decision = self.decision_owner;
        const prior_callback = self.resolver_callback;
        self.decision_owner = null;
        self.resolver_callback = 0;
        defer self.decision_owner = prior_decision;
        defer self.resolver_callback = prior_callback;
        var owner: CallOwner = .{ .module = self.m, .binding = body.binding, .parent = self.active_calls };
        self.active_calls = &owner;
        defer self.active_calls = owner.parent;
        try self.node(body.root, parameters, body.closed_rows, depth + 1);
    }

    const RowOwner = struct { closed: T.List, generic: T.List, parent: ?*const RowOwner };
    fn knownInstance(self: *Named, identity: T.NominalIdentity) Error!bool {
        if (identity.decl == 0) return true;
        var owner = self.scope_owner;
        while (owner) |current| : (owner = current.parent) {
            try self.step(0);
            if (std.meta.eql(identity, current.identity)) return true;
        }
        return false;
    }
    fn token(self: *Named, id: T.Id, depth: usize) Error!void {
        try self.step(depth);
        var node_ = self.m.types.node(id);
        if (node_.tag == .scoped) {
            try require(try self.knownInstance(.{ .unit = node_.b, .decl = node_.c }));
            const family = self.m.types.node(node_.a);
            if (family.tag == .nominal and family.a == @import("task_types.zig").view.unit and family.b == @import("task_types.zig").view.decl) {
                var owner = self.scope_owner;
                while (owner) |current| : (owner = current.parent) {
                    try self.step(depth);
                    if (current.task_view != id) continue;
                    const arguments = self.m.types.nominalArguments(family);
                    try require(arguments.len == 2 and self.m.types.node(arguments[1]).tag == .instance_version);
                    return self.data(arguments[0], depth + 1);
                }
                return error.InvalidArtifact;
            }
            node_ = self.m.types.node(node_.a);
        }
        try require(node_.tag == .nominal);
        for (self.m.types.nominalArguments(node_)) |argument| try self.data(argument, depth + 1);
    }
    fn dataRow(self: *Named, id: T.Effects.Id, depth: usize) Error!void {
        for (self.m.types.rowLabels(id)) |label| {
            try self.step(depth);
            const operation = self.m.types.operations[label];
            try require(try self.knownInstance(operation.instance));
            for (self.m.types.list(operation.arguments)) |argument| try self.data(argument, depth + 1);
        }
    }
    fn ownedTail(self: *Named, id: T.Effects.Id, closed_rows: T.List) bool {
        const tail = self.m.types.row(id).tail;
        if (tail == .closed) return true;
        if (tail != .variable) return false;
        if (std.mem.findScalar(u32, self.m.types.list(closed_rows), tail.variable) != null or std.mem.findScalar(u32, self.m.types.list(self.row_variables), tail.variable) != null) return true;
        var owner = self.row_owners;
        while (owner) |current| : (owner = current.parent) {
            if (std.mem.findScalar(u32, self.m.types.list(current.closed), tail.variable) != null or std.mem.findScalar(u32, self.m.types.list(current.generic), tail.variable) != null) return true;
        }
        return false;
    }
    fn initializeViews(self: *Named, closed_rows: T.List, context: *@import("package_contracts.zig").Context, depth: usize) Error!void {
        try context.initialize();
        for (self.m.types.effects.rows, 0..) |row, index| {
            try self.step(depth);
            if (row.tail != .variable) continue;
            var closed = std.mem.findScalar(u32, self.m.types.list(closed_rows), row.tail.variable) != null;
            var owner = self.row_owners;
            while (owner) |current| : (owner = current.parent) {
                try self.step(depth);
                if (std.mem.findScalar(u32, self.m.types.list(current.closed), row.tail.variable) != null) closed = true;
            }
            if (!closed) continue;
            context.closed_rows[index] = true;
            if (row.labels.len == 0) context.pure_rows[index] = true;
        }
    }
    fn step(self: *Named, depth: usize) Error!void {
        try require(depth < 128 and self.remaining.* != 0);
        self.remaining.* -= 1;
    }
    fn binders(self: *Named, body: *const core.Body) Error![]const T.Id {
        try require(!body.runtime and body.scheme.generative.len == 0);
        const rows = self.m.types.list(body.scheme.row_variables);
        try require(rows.len <= 128);
        for (rows, 0..) |variable, index| {
            try require(variable < self.m.types.effects.variable_count and std.mem.findScalar(u32, rows[0..index], variable) == null);
        }
        const variables = self.m.types.list(body.scheme.variables);
        try require(variables.len <= 32);
        for (variables, 0..) |variable, index| {
            try require(self.m.types.node(variable).tag == .variable);
            try require(std.mem.findScalar(T.Id, variables[0..index], variable) == null);
        }
        return variables;
    }
    fn local(self: *Named, binding: core.BindingId) Error!bool {
        var scope = self.locals;
        while (scope) |current| : (scope = current.parent) {
            for (current.parameters) |parameter| {
                try self.step(0);
                if (parameter.binding == binding) return true;
            }
            for (current.bindings) |owned| {
                try self.step(0);
                if (owned == binding) return true;
            }
        }
        return false;
    }
    fn constructorVariables(self: *Named, owner: u32, constructor: core.Constructor) Error![]const T.Id {
        try require(constructor.nominal == owner and constructor.scheme.obligations.len == 0 and constructor.scheme.row_variables.len == 0 and constructor.scheme.generative.len == 0);
        const variables = self.m.types.list(constructor.scheme.variables);
        try require(variables.len <= 32);
        for (variables, 0..) |variable, position| {
            try require(self.m.types.node(variable).tag == .variable and std.mem.findScalar(T.Id, variables[0..position], variable) == null);
            try require(std.mem.findScalar(T.Id, self.m.types.list(self.m.nominals[owner].variables), variable) != null);
        }
        return variables;
    }
    fn data(self: *Named, id: T.Id, depth: usize) Error!void {
        try self.step(depth);
        const n = self.m.types.node(id);
        switch (n.tag) {
            .unit, .boolean, .u32, .f32, .never => {},
            .variable => try require(std.mem.findScalar(T.Id, self.variables, id) != null),
            .existential => {
                var context: @import("package_contracts.zig").Context = .{ .types = &self.m.types, .remaining = self.remaining };
                try context.initialize();
                try context.visit(id);
            },
            .array, .list, .cursor => try self.data(n.a, depth + 1),
            .usage => {
                const kind: T.UsageKind = @fromBackingInt(n.b);
                if (kind == .borrow or kind == .borrow_mut) {
                    var owner = self.loan_owner;
                    var found = false;
                    while (owner) |current| : (owner = current.parent) {
                        try self.step(depth);
                        if (current.region == n.c) found = true;
                    }
                    try require(n.c != 0 and found);
                } else if (kind == .concurrent) {
                    try require(n.c == 0 and @import("task_types.zig").concurrentHost(&self.m.types, n.a));
                } else try require(n.c == 0 and (kind == .unique or kind == .shared or kind == .once or kind == .many or kind == .cleanup));
                try self.data(n.a, depth + 1);
            },
            .function => {
                try require(self.ownedTail(n.c, self.data_rows));
                try self.dataRow(n.c, depth + 1);
                try self.data(n.a, depth + 1);
                try self.data(n.b, depth + 1);
            },
            .product => for (self.m.types.list(.{ .start = n.a, .len = n.b })) |child| try self.data(child, depth + 1),
            .record => for (0..n.b) |index| try self.data(self.m.types.recordField(n, index).ty, depth + 1),
            .type_constructor => {
                try require(n.c == 0);
                var found = false;
                for (self.m.nominals) |family| if (family.identity.unit == n.a and family.identity.decl == n.b) {
                    found = true;
                };
                try require(found);
            },
            .resolver => {
                try require(n.b == 0 and n.c == 0 and self.m.types.node(n.a).tag == .type_constructor);
                try self.data(n.a, depth + 1);
            },
            .scoped => try self.token(id, depth + 1),
            .provider => {
                try self.token(n.a, depth + 1);
                try self.dataRow(n.c, depth + 1);
            },
            .state_provider => {
                try self.token(n.a, depth + 1);
                try self.token(n.b, depth + 1);
                try self.data(n.c, depth + 1);
            },
            .nominal => {
                if (n.a == std.math.maxInt(u32) and (n.b == 5 or n.b == 6)) {
                    const arguments = self.m.types.nominalArguments(n);
                    try require(arguments.len == @as(usize, if (n.b == 5) 1 else 3));
                    if (n.b == 5) {
                        const action = try callable(self.m, arguments[0], self.remaining);
                        try require(action.a == T.unit);
                    }
                    for (arguments) |argument| try self.data(argument, depth + 1);
                    return;
                }
                if (n.a == @import("task_types.zig").handle.unit and n.b == @import("task_types.zig").handle.decl) {
                    const arguments = self.m.types.nominalArguments(n);
                    try require(arguments.len == 2 and @import("task_types.zig").isGroup(&self.m.types, arguments[0]) and self.m.types.node(arguments[1]).tag == .function);
                    try self.token(arguments[0], depth + 1);
                    return self.data(arguments[1], depth + 1);
                }
                for (self.m.types.nominalArguments(n)) |child| try self.data(child, depth + 1);
                const owner = try nominalOwner(self.m, n, self.remaining);
                const family = self.m.nominals[owner];
                try require(self.m.types.nominalArguments(n).len == family.parameters.len);
                for (self.m.nominalConstructors(owner), 0..) |index, ordinal| {
                    try self.step(depth);
                    const constructor = self.m.constructors[index];
                    try require(constructor.tag == ordinal);
                    const variables = try self.constructorVariables(owner, constructor);
                    var bindings: [32]T.Id = @splat(0);
                    const output = try self.constructorResult(constructor, depth + 1);
                    try self.match(output, id, variables, &bindings, depth + 1);
                    for (bindings[0..variables.len]) |binding| try require(binding != 0);
                    const caller_variables = self.variables;
                    self.variables = variables;
                    defer self.variables = caller_variables;
                    if (constructor.payload != 0) try self.data(constructor.payload, depth + 1);
                }
            },
            else => return error.InvalidArtifact,
        }
    }
    fn constructorResult(self: *Named, constructor: core.Constructor, depth: usize) Error!T.Id {
        try self.step(depth);
        if (constructor.payload == 0) return constructor.scheme.root;
        const arrow = self.m.types.node(constructor.scheme.root);
        try require(arrow.tag == .function and sameRow(self.m, arrow.c, 0, .{}));
        if (self.m.nominals[constructor.nominal].is_opaque) {
            try require(try equal(self.m, arrow.a, constructor.payload, 0, self.remaining));
            return arrow.b;
        }
        const payload = self.m.types.node(constructor.payload);
        if (payload.tag == .record) {
            if (payload.b == 1) {
                try require(try equal(self.m, arrow.a, self.m.types.recordField(payload, 0).ty, 0, self.remaining));
            } else {
                const input = self.m.types.node(arrow.a);
                try require(input.tag == .product and input.b == payload.b);
                for (self.m.types.list(.{ .start = input.a, .len = input.b }), 0..) |part, index| {
                    try require(try equal(self.m, part, self.m.types.recordField(payload, index).ty, 0, self.remaining));
                }
            }
        } else try require(try equal(self.m, arrow.a, constructor.payload, 0, self.remaining));
        return arrow.b;
    }
    fn match(self: *Named, formal: T.Id, actual: T.Id, variables: []const T.Id, bindings: []T.Id, depth: usize) Error!void {
        try self.step(depth);
        const from = self.m.types.node(formal);
        if (from.tag == .variable) {
            const index = std.mem.findScalar(T.Id, variables, formal) orelse return error.InvalidArtifact;
            if (bindings[index] == 0) bindings[index] = actual else try require(try equal(self.m, bindings[index], actual, 0, self.remaining));
            return;
        }
        const to = self.m.types.node(actual);
        try require(from.tag == to.tag);
        switch (from.tag) {
            .unit, .boolean, .u32, .f32, .never => {},
            .array, .list => try self.match(from.a, to.a, variables, bindings, depth + 1),
            .usage => {
                try require(from.b == to.b and from.c == to.c);
                try self.match(from.a, to.a, variables, bindings, depth + 1);
            },
            .product => {
                try require(from.b == to.b);
                for (self.m.types.list(.{ .start = from.a, .len = from.b }), self.m.types.list(.{ .start = to.a, .len = to.b })) |left, right| try self.match(left, right, variables, bindings, depth + 1);
            },
            .record => {
                try require(from.b == to.b);
                for (0..from.b) |index| {
                    const left = self.m.types.recordField(from, index);
                    const right = self.m.types.recordField(to, index);
                    try require(left.name == right.name);
                    try self.match(left.ty, right.ty, variables, bindings, depth + 1);
                }
            },
            .nominal => {
                try require(from.a == to.a and from.b == to.b);
                const left = self.m.types.nominalArguments(from);
                const right = self.m.types.nominalArguments(to);
                try require(left.len == right.len);
                for (left, right) |x, y| try self.match(x, y, variables, bindings, depth + 1);
            },
            .function => {
                try require(sameRow(self.m, from.c, to.c, .{}));
                try self.match(from.a, to.a, variables, bindings, depth + 1);
                try self.match(from.b, to.b, variables, bindings, depth + 1);
            },
            .existential => {
                var proof: @import("package_contracts.zig").Principal = .{ .left = &self.m.types, .right = &self.m.types, .remaining = self.remaining };
                try proof.validate(formal, actual);
            },
            else => try require(try equal(self.m, formal, actual, 0, self.remaining)),
        }
    }
    fn call(self: *Named, id: core.Id, caller_rows: T.List, depth: usize) Error!*const core.Body {
        try self.step(depth);
        const saved_rows = self.data_rows;
        self.data_rows = caller_rows;
        defer self.data_rows = saved_rows;
        const call_ = try executableCall(self.m, self.units, id, self.remaining, self.workspace);
        const prior_callback = self.resolver_callback;
        defer self.resolver_callback = prior_callback;
        if (self.m.node(id).tag == .resolver_op) {
            const operation = self.m.resolverInfo(id).operation;
            if (operation == .bind or operation == .iterate) self.resolver_callback = call_.arguments[1];
        }
        for (call_.arguments) |argument| try self.node(argument, self.parameters, caller_rows, depth + 1);
        if (call_.target.unit != 0 and call_.target.unit != self.m.unit) return self.foreignCall(id, caller_rows, depth + 1);
        const binding = self.m.bindings[call_.target.binding];
        try require(binding.kind == .global);
        const body = self.m.body(call_.target.binding) orelse return error.InvalidArtifact;
        try require(body.is_function);
        if (self.m.types.node(binding.ty).tag == .forall) return self.universalCall(id, self.m, body, caller_rows, depth + 1);
        if (body.scheme.obligations.len != 0) return self.qualifiedCall(id, self.m, body, caller_rows, depth + 1);
        if (body.scheme.row_variables.len != 0) return self.rowCall(id, self.m, body, caller_rows, depth + 1);
        const variables = try self.binders(body);
        var bindings: [32]T.Id = @splat(0);
        const parameters = self.m.bodyParameters(body);
        try require(call_.arguments.len == parameters.len);
        var signature = binding.ty;
        var selected = call_.callee_type;
        var body_row: T.Effects.Id = 0;
        for (parameters, call_.arguments, 0..) |parameter, argument, position| {
            const arrow = self.m.types.node(signature);
            try require(arrow.tag == .function);
            const use = self.m.types.node(selected);
            try require(use.tag == .function);
            try require(self.ownedTail(use.c, caller_rows));
            try self.data(use.a, depth + 1);
            try self.match(arrow.a, use.a, variables, &bindings, depth + 1);
            const row = self.m.types.effects.node(arrow.c);
            try require(row.tail == .closed or (row.tail == .variable and std.mem.findScalar(u32, self.m.types.list(body.closed_rows), row.tail.variable) != null));
            if (position + 1 != parameters.len) try require(row.labels.len == 0);
            try require(try authorityRow(self.m, arrow.c, depth + 1, self.remaining));
            body_row = arrow.c;
            try require(try equal(self.m, arrow.a, parameter.ty, 0, self.remaining));
            try require(try equal(self.m, use.a, self.m.typeOf(argument), 0, self.remaining));
            signature = arrow.b;
            selected = use.b;
        }
        try self.data(selected, depth + 1);
        try self.match(signature, selected, variables, &bindings, depth + 1);
        try require(try equal(self.m, selected, self.m.typeOf(id), 0, self.remaining));
        try require(self.m.typeOf(body.root) == T.never or try equal(self.m, signature, self.m.typeOf(body.root), 0, self.remaining));
        const caller_variables = self.variables;
        const caller_row_variables = self.row_variables;
        const caller_locals = self.locals;
        const caller_loop = self.loop_owner;
        const caller_row_owners = self.row_owners;
        const caller_loan = self.loan_owner;
        self.variables = variables;
        self.row_variables = body.scheme.row_variables;
        self.locals = null;
        self.loop_owner = null;
        self.row_owners = null;
        self.loan_owner = null;
        defer self.variables = caller_variables;
        defer self.row_variables = caller_row_variables;
        defer self.locals = caller_locals;
        defer self.loop_owner = caller_loop;
        defer self.row_owners = caller_row_owners;
        defer self.loan_owner = caller_loan;
        try self.declaredBody(body, parameters, depth + 1);
        // A selected signature never proves its own effects. Reconstruct the
        // actual executable body against the producer's own row certificate.
        var effects: Effects = .{ .workspace = self.workspace, .ambient = self.m.types.row(body_row), .m = self.m, .units = self.units, .target_module = self.m, .target = self.m.types.effects.node(body_row), .closed_rows = body.closed_rows, .remaining = self.remaining, .checked_calls = true };
        try require(effects.target.labels.len <= effects.seen.len);
        try effects.visit(body.root, depth + 1);
        try selectedEffects(self.m, self.units, id, self.m, body, caller_rows, caller_variables, variables, &bindings, null, self.row_owners, self.ambient, self.remaining, self.workspace, depth + 1);
        return body;
    }
    fn qualifiedInstance(self: *Named, producer: *const core.Module, body: *const core.Body, actual: T.Id, caller_rows: T.List, depth: usize) Error!@import("package_contracts.zig").Principal {
        try require(!body.runtime and body.scheme.generative.len == 0);
        var views: @import("package_contracts.zig").Context = .{ .types = &self.m.types, .remaining = self.remaining, .obligations = self.m.obligations, .executable = true };
        try self.initializeViews(caller_rows, &views, depth);
        if (self.current_scheme) |scheme| try views.generic(scheme);
        const reference: core.BindingRef = .{ .unit = producer.unit, .binding = body.binding };
        var proof = if (self.workspace) |workspace| try @import("package_core.zig").callInstanceWorkspace(self.m, reference, actual, .{ .units = self.units }, &views, self.remaining, workspace) else try @import("package_core.zig").callInstance(self.m, reference, actual, .{ .units = self.units }, &views, self.remaining);
        if (self.workspace) |workspace| {
            try @import("package_core.zig").parametricBodyWorkspace(producer, body.binding, .{ .units = self.units }, self.remaining, workspace);
        } else try @import("package_core.zig").parametricBody(producer, body.binding, .{ .units = self.units }, self.remaining);
        proof.views = null;
        return proof;
    }
    fn qualifiedCall(self: *Named, id: core.Id, producer: *const core.Module, body: *const core.Body, caller_rows: T.List, depth: usize) Error!*const core.Body {
        const call_ = try executableCall(self.m, self.units, id, self.remaining, self.workspace);
        var instance = try self.qualifiedInstance(producer, body, call_.callee_type, caller_rows, depth + 1);
        var signature = call_.callee_type;
        try require(call_.arguments.len == body.parameters.len);
        for (call_.arguments) |argument| {
            const arrow = try callable(self.m, signature, self.remaining);
            try require(self.ownedTail(arrow.c, caller_rows));
            try require(try equal(self.m, arrow.a, self.m.typeOf(argument), 0, self.remaining));
            try self.data(arrow.a, depth + 1);
            signature = arrow.b;
        }
        try require(try equal(self.m, signature, self.m.typeOf(id), 0, self.remaining));
        try self.data(signature, depth + 1);
        const variables = producer.types.list(body.scheme.variables);
        try require(variables.len <= 32);
        try selectedEffects(self.m, self.units, id, producer, body, caller_rows, self.variables, variables, &instance.witnesses, &instance, self.row_owners, self.ambient, self.remaining, self.workspace, depth + 1);
        return body;
    }
    fn universalInstance(self: *Named, producer: *const core.Module, body: *const core.Body, actual: T.Id, caller_rows: T.List, depth: usize) Error!void {
        var views: @import("package_contracts.zig").Context = .{ .types = &self.m.types, .remaining = self.remaining };
        try self.initializeViews(caller_rows, &views, depth);
        if (self.current_scheme) |scheme| try views.generic(scheme);
        var instance: @import("package_contracts.zig").Principal = .{ .left = &producer.types, .right = &self.m.types, .remaining = self.remaining, .views = &views, .left_rows = body.closed_rows, .foreign_views = true };
        if (self.m.types.node(actual).tag == .forall) try instance.validate(body.scheme.root, actual) else try instance.instantiate(body.scheme.root, actual);
        if (self.workspace) |workspace| {
            try @import("package_core.zig").parametricBodyWorkspace(producer, body.binding, .{ .units = self.units }, self.remaining, workspace);
        } else try @import("package_core.zig").parametricBody(producer, body.binding, .{ .units = self.units }, self.remaining);
    }
    fn universalCall(self: *Named, id: core.Id, producer: *const core.Module, body: *const core.Body, caller_rows: T.List, depth: usize) Error!*const core.Body {
        const call_ = try executableCall(self.m, self.units, id, self.remaining, self.workspace);
        try self.universalInstance(producer, body, call_.callee_type, caller_rows, depth);
        var signature = call_.callee_type;
        try require(call_.arguments.len == body.parameters.len);
        for (call_.arguments) |argument| {
            const arrow = try callable(self.m, signature, self.remaining);
            try require(self.ownedTail(arrow.c, caller_rows));
            try require(try equal(self.m, arrow.a, self.m.typeOf(argument), 0, self.remaining));
            try self.data(arrow.a, depth + 1);
            signature = arrow.b;
        }
        try require(try equal(self.m, signature, self.m.typeOf(id), 0, self.remaining));
        try self.data(signature, depth + 1);
        return body;
    }
    fn foreignCall(self: *Named, id: core.Id, caller_rows: T.List, depth: usize) Error!*const core.Body {
        const call_ = try executableCall(self.m, self.units, id, self.remaining, self.workspace);
        const producer = try targetOwner(self.m, self.units, call_.target, self.workspace);
        const binding = producer.bindings[call_.target.binding];
        try require(binding.kind == .global);
        const body = producer.body(call_.target.binding) orelse return error.InvalidArtifact;
        try require(body.is_function);
        if (producer.types.node(binding.ty).tag == .forall) return self.universalCall(id, producer, body, caller_rows, depth + 1);
        if (body.scheme.obligations.len != 0) return self.qualifiedCall(id, producer, body, caller_rows, depth + 1);
        if (body.scheme.row_variables.len != 0) return self.rowCall(id, producer, body, caller_rows, depth + 1);
        var proof: Named = .{ .workspace = self.workspace, .m = producer, .units = self.units, .remaining = self.remaining, .active_calls = self.active_calls };
        const variables = try proof.binders(body);
        const parameters = producer.bodyParameters(body);
        try require(call_.arguments.len == parameters.len);
        var substitutions: [32]T.Id = @splat(0);
        var signature = binding.ty;
        var selected = call_.callee_type;
        var body_row: T.Effects.Id = 0;
        for (parameters, call_.arguments, 0..) |parameter, argument, position| {
            try self.step(depth);
            const formal = producer.types.node(signature);
            const actual = self.m.types.node(selected);
            try require(formal.tag == .function and actual.tag == .function);
            const formal_row = producer.types.row(formal.c);
            try require(formal_row.tail == .closed or (formal_row.tail == .variable and std.mem.findScalar(u32, producer.types.list(body.closed_rows), formal_row.tail.variable) != null));
            try require(self.ownedTail(actual.c, caller_rows));
            if (position + 1 != parameters.len) try require(formal_row.labels.len == 0);
            try require(try authorityRow(producer, formal.c, depth + 1, self.remaining));
            try self.data(actual.a, depth + 1);
            try cross.match(producer, formal.a, self.m, actual.a, variables, &substitutions, self.remaining, depth + 1);
            try require(try equal(producer, formal.a, parameter.ty, 0, self.remaining));
            try require(try equal(self.m, actual.a, self.m.typeOf(argument), 0, self.remaining));
            body_row = formal.c;
            signature = formal.b;
            selected = actual.b;
        }
        try self.data(selected, depth + 1);
        try cross.match(producer, signature, self.m, selected, variables, &substitutions, self.remaining, depth + 1);
        try require(try equal(self.m, selected, self.m.typeOf(id), 0, self.remaining));
        try require(producer.typeOf(body.root) == T.never or try equal(producer, signature, producer.typeOf(body.root), 0, self.remaining));
        proof.variables = variables;
        try proof.declaredBody(body, parameters, depth + 1);
        var effects: Effects = .{ .workspace = self.workspace, .ambient = producer.types.row(body_row), .m = producer, .units = self.units, .target_module = producer, .target = producer.types.row(body_row), .closed_rows = body.closed_rows, .remaining = self.remaining, .checked_calls = true };
        try require(effects.target.labels.len <= effects.seen.len);
        try effects.visit(body.root, depth + 1);
        try selectedEffects(self.m, self.units, id, producer, body, caller_rows, self.variables, variables, &substitutions, null, self.row_owners, self.ambient, self.remaining, self.workspace, depth + 1);
        return body;
    }
    fn rowCall(self: *Named, id: core.Id, producer: *const core.Module, body: *const core.Body, caller_rows: T.List, depth: usize) Error!*const core.Body {
        var proof: Named = .{ .workspace = self.workspace, .m = producer, .units = self.units, .remaining = self.remaining, .row_variables = body.scheme.row_variables, .active_calls = self.active_calls };
        if (producer == self.m) proof.scope_owner = self.scope_owner;
        proof.variables = try proof.binders(body);
        const call_ = try executableCall(self.m, self.units, id, self.remaining, self.workspace);
        const parameters = producer.bodyParameters(body);
        try require(call_.arguments.len == parameters.len);
        var views: @import("package_contracts.zig").Context = .{ .types = &self.m.types, .remaining = self.remaining };
        try self.initializeViews(caller_rows, &views, depth);
        if (self.current_scheme) |scheme| try views.generic(scheme);
        var instance: @import("package_contracts.zig").Principal = .{ .left = &producer.types, .right = &self.m.types, .remaining = self.remaining, .views = &views, .left_rows = body.closed_rows, .foreign_views = true };
        try instance.instantiateScheme(body.scheme, call_.callee_type);
        var formal = producer.binding(body.binding).ty;
        var selected = call_.callee_type;
        var body_row: T.Effects.Id = 0;
        for (parameters, call_.arguments, 0..) |parameter, argument, position| {
            const arrow = producer.types.node(formal);
            const use = self.m.types.node(selected);
            try require(arrow.tag == .function and use.tag == .function);
            try require(proof.ownedTail(arrow.c, body.closed_rows) and self.ownedTail(use.c, caller_rows));
            try require(position + 1 == parameters.len or producer.types.rowLabels(arrow.c).len == 0);
            try require(try authorityRow(producer, arrow.c, depth + 1, self.remaining));
            try require(try equal(producer, arrow.a, parameter.ty, 0, self.remaining));
            var argument_proof: @import("package_contracts.zig").Principal = .{ .left = &self.m.types, .right = &self.m.types, .remaining = self.remaining, .views = &views, .foreign_views = true };
            if (self.m.node(argument).tag == .closure) argument_proof.left_rows = self.m.closure(argument).closed_rows;
            try argument_proof.validate(self.m.typeOf(argument), use.a);
            try self.data(use.a, depth + 1);
            formal = arrow.b;
            selected = use.b;
            body_row = arrow.c;
        }
        try self.data(selected, depth + 1);
        try require(try equal(self.m, selected, self.m.typeOf(id), 0, self.remaining));
        try result(producer, formal, producer.typeOf(body.root), self.remaining);
        try proof.declaredBody(body, parameters, depth + 1);
        var effects: Effects = .{ .workspace = self.workspace, .ambient = producer.types.row(body_row), .m = producer, .units = self.units, .target_module = producer, .target = producer.types.row(body_row), .closed_rows = body.closed_rows, .remaining = self.remaining, .checked_calls = true, .variables = proof.variables };
        try require(effects.target.labels.len <= effects.seen.len);
        try effects.visit(body.root, depth + 1);
        try selectedEffects(self.m, self.units, id, producer, body, caller_rows, self.variables, proof.variables, &instance.witnesses, &instance, self.row_owners, self.ambient, self.remaining, self.workspace, depth + 1);
        return body;
    }
    fn foreignData(self: *Named, id: core.Id, reference: core.BindingRef, depth: usize) Error!void {
        const producer = try targetOwner(self.m, self.units, reference, self.workspace);
        const binding = producer.bindings[reference.binding];
        try require(binding.kind == .global);
        const body = producer.body(reference.binding) orelse return error.InvalidArtifact;
        if (body.is_function) return self.functionValue(id, reference, depth + 1);
        try require(body.parameters.len == 0);
        var proof: Named = .{ .workspace = self.workspace, .m = producer, .units = self.units, .remaining = self.remaining };
        const variables = try proof.binders(body);
        var substitutions: [32]T.Id = @splat(0);
        try cross.match(producer, binding.ty, self.m, self.m.typeOf(id), variables, &substitutions, self.remaining, depth + 1);
        try require(producer.typeOf(body.root) == T.never or try equal(producer, binding.ty, producer.typeOf(body.root), 0, self.remaining));
        proof.variables = variables;
        try proof.node(body.root, &.{}, body.closed_rows, depth + 1);
        var effects: Effects = .{ .workspace = self.workspace, .m = producer, .units = self.units, .target_module = producer, .target = producer.types.row(0), .closed_rows = body.closed_rows, .remaining = self.remaining, .checked_calls = true, .variables = variables };
        try effects.visit(body.root, depth + 1);
    }
    fn functionValue(self: *Named, id: core.Id, reference: core.BindingRef, depth: usize) Error!void {
        const producer = try targetOwner(self.m, self.units, reference, self.workspace);
        const binding = producer.bindings[reference.binding];
        const body = producer.body(reference.binding) orelse return error.InvalidArtifact;
        try require(binding.kind == .global and body.is_function);
        if (producer.types.node(binding.ty).tag == .forall) return self.universalInstance(producer, body, self.m.typeOf(id), self.data_rows, depth);
        if (body.scheme.obligations.len != 0) {
            _ = try self.qualifiedInstance(producer, body, self.m.typeOf(id), self.data_rows, depth + 1);
            return;
        }
        var proof: Named = .{ .workspace = self.workspace, .m = producer, .units = self.units, .remaining = self.remaining, .row_variables = body.scheme.row_variables, .active_calls = self.active_calls };
        const variables = try proof.binders(body);
        var views: @import("package_contracts.zig").Context = .{ .types = &self.m.types, .remaining = self.remaining };
        try self.initializeViews(self.data_rows, &views, depth);
        var principal: @import("package_contracts.zig").Principal = .{ .left = &producer.types, .right = &self.m.types, .remaining = self.remaining, .views = &views, .left_rows = body.closed_rows, .foreign_views = true };
        try principal.instantiateScheme(body.scheme, self.m.typeOf(id));
        var signature = binding.ty;
        var row: T.Effects.Id = 0;
        const parameters = producer.bodyParameters(body);
        for (parameters, 0..) |parameter, index| {
            const arrow = producer.types.node(signature);
            try require(arrow.tag == .function and try equal(producer, arrow.a, parameter.ty, 0, self.remaining));
            const declared = producer.types.row(arrow.c);
            try require(proof.ownedTail(arrow.c, body.closed_rows));
            if (index + 1 != parameters.len) try require(declared.labels.len == 0);
            try require(try authorityRow(producer, arrow.c, depth + 1, self.remaining));
            row = arrow.c;
            signature = arrow.b;
        }
        try result(producer, signature, producer.typeOf(body.root), self.remaining);
        proof.variables = variables;
        try proof.declaredBody(body, parameters, depth + 1);
        var effects: Effects = .{ .workspace = self.workspace, .ambient = producer.types.row(row), .m = producer, .units = self.units, .target_module = producer, .target = producer.types.row(row), .closed_rows = body.closed_rows, .remaining = self.remaining, .checked_calls = true, .variables = variables };
        try require(effects.target.labels.len <= effects.seen.len);
        try effects.visit(body.root, depth + 1);
    }
    fn block(self: *Named, id: core.Id, parameters: []const core.Parameter, closed_rows: T.List, depth: usize) Error!void {
        const returns = try self.sequence(id, id, parameters, closed_rows, depth);
        try require(returns or self.m.typeOf(id) == T.unit);
    }
    // Suites retain their branch locals and the enclosing block's return
    // owner. Both branches are proved, including the one not executed now.
    fn branch(self: *Named, id: core.Id, owner: core.Id, parameters: []const core.Parameter, closed_rows: T.List, depth: usize) Error!bool {
        if (id == 0) return false;
        try self.step(depth);
        const n = self.m.node(id);
        try require(n.tag == .suite and n.ty == T.unit);
        return self.sequence(id, owner, parameters, closed_rows, depth + 1);
    }
    fn sequence(self: *Named, id: core.Id, owner: core.Id, parameters: []const core.Parameter, closed_rows: T.List, depth: usize) Error!bool {
        var bindings: [256]core.BindingId = undefined;
        var scope: Locals = .{ .parent = self.locals };
        self.locals = &scope;
        defer self.locals = scope.parent;
        return self.sequenceInto(id, owner, parameters, closed_rows, &scope, &bindings, depth);
    }
    fn known(self: *Named, binding: core.BindingId, parameters: []const core.Parameter) Error!bool {
        for (parameters) |parameter| if (parameter.binding == binding) return true;
        return self.local(binding);
    }
    fn declare(self: *Named, binding: core.BindingId, scope: *Locals, bindings: []core.BindingId, parameters: []const core.Parameter) Error!void {
        try require(scope.bindings.len < bindings.len and !try self.known(binding, parameters));
        try require(self.m.bindings[binding].kind == .local);
        bindings[scope.bindings.len] = binding;
        scope.bindings = bindings[0 .. scope.bindings.len + 1];
    }
    fn sequenceInto(self: *Named, id: core.Id, owner: core.Id, parameters: []const core.Parameter, closed_rows: T.List, scope: *Locals, bindings: []core.BindingId, depth: usize) Error!bool {
        const children = self.m.children(id);
        for (children, 0..) |child, index| {
            try self.step(depth);
            const n = self.m.node(child);
            if (n.tag == .bind) {
                const binding = self.m.bindings[n.a];
                try require(n.ty == T.unit and binding.initializer == n.b);
                const request_state = binding.kind == .parameter and self.decision_owner != null;
                try require(binding.kind == .local or request_state);
                try require(binding.scheme.variables.len == 0 and binding.scheme.row_variables.len == 0 and binding.scheme.obligations.len == 0 and binding.scheme.generative.len == 0);
                try require(try equal(self.m, binding.ty, self.m.typeOf(n.b), 0, self.remaining));
                try self.node(n.b, parameters, closed_rows, depth + 1);
                if (request_state) {
                    try require(!try self.known(n.a, parameters) and scope.bindings.len < bindings.len);
                    bindings[scope.bindings.len] = n.a;
                    scope.bindings = bindings[0 .. scope.bindings.len + 1];
                } else try self.declare(n.a, scope, bindings, parameters);
            } else if (n.tag == .pattern_bind) {
                try require(n.ty == T.unit);
                try self.node(n.b, parameters, closed_rows, depth + 1);
                if (n.c != 0) try require(try self.branch(n.c, owner, parameters, closed_rows, depth + 1));
                try self.patternMode(n.a, self.m.typeOf(n.b), bindings, scope, parameters, n.c != 0, depth + 1);
            } else if (n.tag == .request_loop) {
                if (try self.requestLoop(child, owner, parameters, closed_rows, scope, bindings, depth + 1)) {
                    try require(index + 1 == children.len);
                    return true;
                }
            } else if (n.tag == .loop) {
                if (try self.loop(child, owner, parameters, closed_rows, scope, bindings, depth + 1)) {
                    try require(index + 1 == children.len);
                    return true;
                }
            } else if (n.tag == .break_) {
                try require(index + 1 == children.len and n.ty == T.never);
                const current = self.loop_owner orelse return error.InvalidArtifact;
                try require(n.a == current.node);
                current.exits = true;
                const carries = if (self.m.node(current.node).tag == .request_loop) self.m.requestLoopCarries(current.node) else self.m.loopCarries(current.node);
                const values = self.m.breakValues(child);
                try require(values.len == carries.len);
                for (values, carries) |value, carry| {
                    try require(try equal(self.m, self.m.typeOf(value), self.m.bindings[carry.iteration].ty, 0, self.remaining));
                    try self.node(value, parameters, closed_rows, depth + 1);
                }
                return true;
            } else if (n.tag == .return_) {
                try require(index + 1 == children.len and n.b == owner and n.ty == T.never);
                try result(self.m, self.m.typeOf(owner), self.m.typeOf(n.a), self.remaining);
                try self.node(n.a, parameters, closed_rows, depth + 1);
                return true;
            } else if (n.tag == .if_stmt) {
                try require(n.ty == T.unit and self.m.typeOf(n.a) == T.boolean);
                try self.node(n.a, parameters, closed_rows, depth + 1);
                if (try self.conditional(child, owner, parameters, closed_rows, scope, bindings, depth + 1)) {
                    try require(index + 1 == children.len);
                    return true;
                }
            } else if (n.tag == .match and self.m.matchInfo(child).statement) {
                if (try self.statementMatch(child, owner, parameters, closed_rows, scope, bindings, depth + 1)) {
                    try require(index + 1 == children.len);
                    return true;
                }
            } else if (n.tag == .suite) {
                if (try self.branch(child, owner, parameters, closed_rows, depth + 1)) {
                    try require(index + 1 == children.len);
                    return true;
                }
            } else {
                try self.node(child, parameters, closed_rows, depth + 1);
                if (n.ty == T.never) {
                    try require(index + 1 == children.len);
                    return true;
                }
            }
        }
        return false;
    }
    fn conditional(self: *Named, id: core.Id, owner: core.Id, parameters: []const core.Parameter, closed_rows: T.List, outer: *Locals, outer_bindings: []core.BindingId, depth: usize) Error!bool {
        const n = self.m.node(id);
        var first_bindings: [256]core.BindingId = undefined;
        var second_bindings: [256]core.BindingId = undefined;
        var first_scope: Locals = .{ .parent = self.locals };
        var second_scope: Locals = .{ .parent = self.locals };
        const parent = self.locals;
        defer self.locals = parent;
        var terminated: [2]bool = @splat(false);
        for ([_]core.Id{ n.b, n.c }, [_]*Locals{ &first_scope, &second_scope }, [_][]core.BindingId{ &first_bindings, &second_bindings }, 0..) |branch_id, branch_scope, storage, branch_index| {
            if (branch_id == 0) continue;
            const branch_node = self.m.node(branch_id);
            try require(branch_node.tag == .suite and branch_node.ty == T.unit);
            self.locals = branch_scope;
            terminated[branch_index] = try self.sequenceInto(branch_id, owner, parameters, closed_rows, branch_scope, storage, depth + 1);
        }
        return self.mergeBranches(id, .{ &first_scope, &second_scope }, terminated, parent, outer, outer_bindings, parameters, depth);
    }
    fn mergeBranches(self: *Named, id: core.Id, branch_scopes: [2]*Locals, terminated: [2]bool, parent: ?*const Locals, outer: *Locals, outer_bindings: []core.BindingId, parameters: []const core.Parameter, depth: usize) Error!bool {
        const merges = self.m.branchMerges(id);
        if (terminated[0] and terminated[1]) try require(merges.len == 0);
        for (merges) |merge| {
            try self.step(depth);
            try require(merge.node == id and self.m.bindings[merge.result].initializer == 0);
            for ([_]core.BindingId{ merge.then_binding, merge.else_binding }, branch_scopes, terminated) |input, branch_scope, exits| {
                if (exits) continue;
                self.locals = branch_scope;
                try require(try self.known(input, parameters));
                try require(try equal(self.m, self.m.bindings[merge.result].ty, self.m.bindings[input].ty, 0, self.remaining));
            }
            self.locals = parent;
            try self.declare(merge.result, outer, outer_bindings, parameters);
        }
        return terminated[0] and terminated[1];
    }
    fn statementMatch(self: *Named, id: core.Id, owner: core.Id, parameters: []const core.Parameter, closed_rows: T.List, outer: *Locals, outer_bindings: []core.BindingId, depth: usize) Error!bool {
        const node_ = self.m.node(id);
        const inputs = self.m.matchInputs(id);
        const arms = self.m.matchArms(id);
        try require(self.m.matchInfo(id).statement and node_.ty == T.unit and node_.b == 0 and node_.c == 0);
        try require(inputs.len == 1 and arms.len == 2);
        try self.node(inputs[0], parameters, closed_rows, depth + 1);
        var first_bindings: [256]core.BindingId = undefined;
        var second_bindings: [256]core.BindingId = undefined;
        const parent = self.locals;
        defer self.locals = parent;
        var first_scope: Locals = .{ .parent = parent };
        var second_scope: Locals = .{ .parent = parent };
        var terminated: [2]bool = @splat(false);
        for (arms, [_]*Locals{ &first_scope, &second_scope }, [_][]core.BindingId{ &first_bindings, &second_bindings }, 0..) |arm, scope, bindings, ordinal| {
            const rows = self.m.armRows(arm);
            try require(rows.len == 1 and arm.guard == 0);
            const patterns = self.m.rowPatterns(rows[0]);
            try require(patterns.len == 1);
            if (ordinal == 1) try require(self.m.pattern(patterns[0]).tag == .wildcard);
            self.locals = scope;
            try self.patternMode(patterns[0], self.m.typeOf(inputs[0]), bindings, scope, parameters, true, depth + 1);
            if (arm.body != 0) {
                try require(self.m.node(arm.body).tag == .suite and self.m.typeOf(arm.body) == T.unit);
                terminated[ordinal] = try self.sequenceInto(arm.body, owner, parameters, closed_rows, scope, bindings, depth + 1);
            }
        }
        return self.mergeBranches(id, .{ &first_scope, &second_scope }, terminated, parent, outer, outer_bindings, parameters, depth);
    }
    fn loop(self: *Named, id: core.Id, owner: core.Id, parameters: []const core.Parameter, closed_rows: T.List, outer: *Locals, outer_bindings: []core.BindingId, depth: usize) Error!bool {
        try self.step(depth);
        const node_ = self.m.node(id);
        const info = self.m.loopInfo(id);
        try require(node_.ty == T.unit and self.m.node(info.body).tag == .suite and self.m.typeOf(info.body) == T.unit);
        var element: T.Id = 0;
        switch (info.kind) {
            .forever => try require(info.first == 0 and info.end == 0 and info.pattern == 0),
            .range => {
                try require(self.m.typeOf(info.first) == T.u32_type and self.m.typeOf(info.end) == T.u32_type);
                try self.node(info.first, parameters, closed_rows, depth + 1);
                try self.node(info.end, parameters, closed_rows, depth + 1);
                element = T.u32_type;
            },
            .array => {
                const collection_ = self.m.types.node(self.m.typeOf(info.first));
                try require(collection_.tag == .array and info.end == 0);
                try self.node(info.first, parameters, closed_rows, depth + 1);
                element = collection_.a;
            },
        }
        var bindings: [256]core.BindingId = undefined;
        var scope: Locals = .{ .parent = self.locals };
        self.locals = &scope;
        defer self.locals = scope.parent;
        const carries = self.m.loopCarries(id);
        for (carries) |carry| {
            try require(try self.known(carry.incoming, parameters));
            const input = self.m.bindings[carry.incoming].ty;
            inline for (.{ "iteration", "backedge", "outgoing" }) |field| try require(try equal(self.m, input, self.m.bindings[@field(carry, field)].ty, 0, self.remaining));
            try require(self.m.bindings[carry.iteration].initializer == 0 and self.m.bindings[carry.outgoing].initializer == 0);
            try self.declare(carry.iteration, &scope, &bindings, parameters);
        }
        if (element != 0) try self.pattern(info.pattern, element, &bindings, &scope, parameters, depth + 1);
        var loop_scope: LoopOwner = .{ .node = id, .parent = self.loop_owner };
        self.loop_owner = &loop_scope;
        defer self.loop_owner = loop_scope.parent;
        const terminated = try self.sequenceInto(info.body, owner, parameters, closed_rows, &scope, &bindings, depth + 1);
        if (!terminated) for (carries) |carry| try require(try self.known(carry.backedge, parameters));
        // Outgoing versions become visible only after proving the complete
        // body. Iteration binders and pattern locals stay within the loop.
        self.locals = scope.parent;
        for (carries) |carry| try self.declare(carry.outgoing, outer, outer_bindings, parameters);
        try require(info.can_exit == loop_scope.exits);
        return info.kind == .forever and !loop_scope.exits;
    }
    fn requestLoop(self: *Named, id: core.Id, owner: core.Id, parameters: []const core.Parameter, closed_rows: T.List, outer: *Locals, outer_bindings: []core.BindingId, depth: usize) Error!bool {
        const info = self.m.requestLoopInfo(id);
        try require(self.m.typeOf(id) == T.unit and info.return_target == owner);
        try require(try equal(self.m, info.result_type, self.m.typeOf(owner), 0, self.remaining));
        try self.node(info.computation, parameters, closed_rows, depth + 1);
        const carries = self.m.requestLoopCarries(id);
        const completion = self.m.requestCompletionBindings(id);
        try require(completion.len == carries.len);
        const state = self.m.types.node(info.state_type);
        if (carries.len == 0) try require(info.state_type == T.unit);
        if (carries.len > 1) try require(state.tag == .product and state.b == carries.len);
        var bindings: [256]core.BindingId = undefined;
        var scope: Locals = .{ .parent = self.locals };
        self.locals = &scope;
        defer self.locals = scope.parent;
        for (carries, completion, 0..) |carry, complete, index| {
            try require(try self.known(carry.incoming, parameters));
            const input = self.m.bindings[carry.incoming].ty;
            var part = info.state_type;
            if (carries.len > 1) part = self.m.types.list(.{ .start = state.a, .len = state.b })[index];
            try require(try equal(self.m, input, part, 0, self.remaining));
            inline for (.{ "iteration", "backedge", "outgoing" }) |field| try require(try equal(self.m, input, self.m.bindings[@field(carry, field)].ty, 0, self.remaining));
            try require(self.m.bindings[carry.iteration].initializer == 0 and self.m.bindings[carry.outgoing].initializer == 0);
            try require(try equal(self.m, input, self.m.bindings[complete].ty, 0, self.remaining) and self.m.bindings[complete].initializer == 0);
            try require(self.m.bindings[complete].kind == .parameter and !try self.known(complete, parameters) and scope.bindings.len < bindings.len);
            bindings[scope.bindings.len] = complete;
            scope.bindings = bindings[0 .. scope.bindings.len + 1];
        }
        // Callback inputs contain their own state projection/binding nodes.
        // Completion locals must never be visible while constructing an arm.
        self.locals = scope.parent;
        var arm_breaks = false;
        for (self.m.requestArms(id)) |arm| {
            const arrow = try callable(self.m, self.m.typeOf(arm.callback), self.remaining);
            var decision_scope: DecisionOwner = .{ .callback = arm.callback, .ty = arrow.b, .breaks = &arm_breaks };
            const parent = self.decision_owner;
            self.decision_owner = &decision_scope;
            defer self.decision_owner = parent;
            try self.node(arm.callback, parameters, closed_rows, depth + 1);
            if (arm.selector != 0) try self.node(arm.selector, parameters, closed_rows, depth + 1);
        }
        self.locals = &scope;
        try self.pattern(info.completion_pattern, info.value_type, &bindings, &scope, parameters, depth + 1);
        var loop_scope: LoopOwner = .{ .node = id, .parent = self.loop_owner };
        self.loop_owner = &loop_scope;
        defer self.loop_owner = loop_scope.parent;
        try require(try self.branch(info.completion_body, owner, parameters, closed_rows, depth + 1));
        self.locals = scope.parent;
        for (carries) |carry| try self.declare(carry.outgoing, outer, outer_bindings, parameters);
        return !arm_breaks and !loop_scope.exits;
    }
    fn decision(self: *Named, id: core.Id, parameters: []const core.Parameter, closed_rows: T.List, depth: usize) Error!void {
        const owner = self.decision_owner orelse return error.InvalidArtifact;
        const n = self.m.node(id);
        try require(try equal(self.m, n.ty, owner.ty, 0, self.remaining));
        const shape = self.m.types.node(owner.ty);
        try require(shape.tag == .nominal and shape.a == std.math.maxInt(u32) and shape.b == 6);
        const parts = self.m.types.nominalArguments(shape);
        try require(parts.len == 3 and n.a <= @backingInt(core.RequestDecisionKind.break_));
        const kind: core.RequestDecisionKind = @fromBackingInt(n.a);
        if (kind == .break_) {
            owner.breaks.* = true;
            try require(n.b == 0);
        } else {
            var expected = parts[0];
            if (kind == .cancel) expected = parts[2];
            try result(self.m, expected, self.m.typeOf(n.b), self.remaining);
            try self.node(n.b, parameters, closed_rows, depth + 1);
        }
        if (kind == .cancel) try require(n.c == 0) else {
            try result(self.m, parts[1], self.m.typeOf(n.c), self.remaining);
            try self.node(n.c, parameters, closed_rows, depth + 1);
        }
    }
    // Builtin Bool constructors lower to canonical scalar patterns. Keep
    // exhaustiveness and disjoint ownership separate from arm execution.
    fn booleanCase(self: *Named, id: core.Id, parameters: []const core.Parameter, closed_rows: T.List, depth: usize) Error!void {
        const n = self.m.node(id);
        const info = self.m.matchInfo(id);
        const inputs = self.m.matchInputs(id);
        const arms = self.m.matchArms(id);
        try require(!info.statement and n.b == 0 and n.c == 0 and self.m.merge_ranges[id].len == 0);
        try require(inputs.len == 1);
        if (self.m.typeOf(inputs[0]) != T.boolean) {
            if (self.m.types.node(self.m.typeOf(inputs[0])).tag == .nominal) return self.nominalCase(id, parameters, closed_rows, depth + 1);
            return self.dataCase(id, parameters, closed_rows, depth + 1);
        }
        try require(arms.len == 2);
        try self.node(inputs[0], parameters, closed_rows, depth + 1);
        var covered: u8 = 0;
        for (arms) |arm| {
            try self.step(depth);
            const rows = self.m.armRows(arm);
            try require(arm.guard == 0 and rows.len == 1);
            const patterns = self.m.rowPatterns(rows[0]);
            try require(patterns.len == 1);
            const literal = self.m.pattern(patterns[0]);
            try require(literal.tag == .constant and literal.ty == T.boolean and literal.a <= 1 and literal.b == 0 and literal.c == 0);
            const bit = @as(u8, 1) << @intCast(literal.a);
            try require(covered & bit == 0);
            covered |= bit;
            try result(self.m, n.ty, self.m.typeOf(arm.body), self.remaining);
            try self.node(arm.body, parameters, closed_rows, depth + 1);
        }
        try require(covered == 3);
    }
    fn irrefutable(self: *Named, id: core.PatternId, depth: usize) Error!bool {
        try self.step(depth);
        const p = self.m.pattern(id);
        switch (p.tag) {
            .wildcard, .bind => return true,
            .product => {
                for (self.m.patternChildren(id)) |child| if (!try self.irrefutable(child, depth + 1)) return false;
                return true;
            },
            .record_payload => return self.irrefutable(p.b, depth + 1),
            .constructor => {
                const owner = try nominalOwner(self.m, self.m.types.node(p.ty), self.remaining);
                if (self.m.nominalConstructors(owner).len != 1) return false;
                if (p.b == 0) return true;
                return self.irrefutable(p.b, depth + 1);
            },
            else => return false,
        }
    }
    fn dataCase(self: *Named, id: core.Id, parameters: []const core.Parameter, closed_rows: T.List, depth: usize) Error!void {
        const input = self.m.matchInputs(id)[0];
        const input_type = self.m.typeOf(input);
        const tag = self.m.types.node(input_type).tag;
        const arms = self.m.matchArms(id);
        try require(arms.len != 0);
        try self.node(input, parameters, closed_rows, depth + 1);
        var complete = false;
        for (arms, 0..) |arm, ordinal| {
            try self.step(depth);
            const rows = self.m.armRows(arm);
            try require(!complete and arm.guard == 0 and rows.len == 1);
            const patterns = self.m.rowPatterns(rows[0]);
            try require(patterns.len == 1);
            const pattern_id = patterns[0];
            const p = self.m.pattern(pattern_id);
            try require(try equal(self.m, input_type, p.ty, 0, self.remaining));
            var bindings: [256]core.BindingId = undefined;
            var scope: Locals = .{ .parent = self.locals };
            self.locals = &scope;
            defer self.locals = scope.parent;
            if (p.tag == .constant) {
                try require((tag == .unit or tag == .u32 or tag == .f32) and p.b == 0 and p.c == 0);
                if (tag == .unit) {
                    try require(p.a == 0);
                    complete = true;
                }
                for (arms[0..ordinal]) |previous| {
                    try self.step(depth);
                    const prior = self.m.pattern(self.m.rowPatterns(self.m.armRows(previous)[0])[0]);
                    if (prior.tag != .constant) continue;
                    if (tag == .f32) {
                        const left: f32 = @bitCast(prior.a);
                        const right: f32 = @bitCast(p.a);
                        try require(left != right);
                    } else try require(prior.a != p.a);
                }
            } else {
                try require(try self.irrefutable(pattern_id, depth + 1));
                try self.pattern(pattern_id, input_type, &bindings, &scope, parameters, depth + 1);
                complete = true;
            }
            try result(self.m, self.m.typeOf(id), self.m.typeOf(arm.body), self.remaining);
            try self.node(arm.body, parameters, closed_rows, depth + 1);
        }
        try require(complete);
    }
    fn pattern(self: *Named, id: core.PatternId, expected: T.Id, bindings: []core.BindingId, scope: *Locals, parameters: []const core.Parameter, depth: usize) Error!void {
        return self.patternMode(id, expected, bindings, scope, parameters, false, depth);
    }
    fn patternMode(self: *Named, id: core.PatternId, expected: T.Id, bindings: []core.BindingId, scope: *Locals, parameters: []const core.Parameter, refutable: bool, depth: usize) Error!void {
        try self.step(depth);
        const p = self.m.pattern(id);
        try require(try equal(self.m, expected, p.ty, 0, self.remaining));
        try self.data(p.ty, depth + 1);
        switch (p.tag) {
            .wildcard => try require(p.a == 0 and p.b == 0 and p.c == 0),
            .bind => {
                const binding = self.m.bindings[p.a];
                try require(p.b == 0 and p.c == 0 and binding.kind == .local and binding.initializer == 0 and scope.bindings.len < bindings.len);
                try require(!try self.local(p.a) and try equal(self.m, binding.ty, p.ty, 0, self.remaining));
                try require(binding.scheme.variables.len == 0 and binding.scheme.row_variables.len == 0 and binding.scheme.obligations.len == 0 and binding.scheme.generative.len == 0);
                for (parameters) |parameter| try require(parameter.binding != p.a);
                bindings[scope.bindings.len] = p.a;
                scope.bindings = bindings[0 .. scope.bindings.len + 1];
            },
            .product => {
                const shape = self.m.types.node(p.ty);
                const children = self.m.patternChildren(id);
                try require((shape.tag == .product or shape.tag == .record) and children.len == shape.b and p.c == 0);
                for (children, 0..) |child, index| {
                    var part: T.Id = 0;
                    if (shape.tag == .product) part = self.m.types.list(.{ .start = shape.a, .len = shape.b })[index] else part = self.m.types.recordField(shape, index).ty;
                    try self.patternMode(child, part, bindings, scope, parameters, refutable, depth + 1);
                }
            },
            .constructor => {
                const owner = try nominalOwner(self.m, self.m.types.node(p.ty), self.remaining);
                // Nested payload patterns must be irrefutable. Top-level
                // constructor coverage is checked separately by nominalCase.
                if (!refutable) try require(self.m.nominalConstructors(owner).len == 1);
                try self.constructorPatternMode(id, bindings, scope, parameters, refutable, depth + 1);
            },
            .record_payload => {
                const shape = self.m.types.node(p.ty);
                const child = self.m.pattern(p.b);
                try require(shape.tag == .record and p.a == shape.b and p.c == 0);
                if (shape.b == 1) {
                    try self.patternMode(p.b, self.m.types.recordField(shape, 0).ty, bindings, scope, parameters, refutable, depth + 1);
                } else {
                    const input = self.m.types.node(child.ty);
                    try require(input.tag == .product and input.b == shape.b);
                    for (self.m.types.list(.{ .start = input.a, .len = input.b }), 0..) |part, index| try require(try equal(self.m, part, self.m.types.recordField(shape, index).ty, 0, self.remaining));
                    try self.patternMode(p.b, child.ty, bindings, scope, parameters, refutable, depth + 1);
                }
            },
            else => return error.InvalidArtifact,
        }
    }
    fn constructorPattern(self: *Named, id: core.PatternId, bindings: []core.BindingId, scope: *Locals, parameters: []const core.Parameter, depth: usize) Error!void {
        return self.constructorPatternMode(id, bindings, scope, parameters, false, depth);
    }
    fn constructorPatternMode(self: *Named, id: core.PatternId, bindings: []core.BindingId, scope: *Locals, parameters: []const core.Parameter, refutable: bool, depth: usize) Error!void {
        try self.step(depth);
        const p = self.m.pattern(id);
        const owner = try nominalOwner(self.m, self.m.types.node(p.ty), self.remaining);
        const constructor = self.m.constructors[p.a];
        try require(p.tag == .constructor and p.c == 0 and constructor.nominal == owner and std.mem.findScalar(u32, self.m.nominalConstructors(owner), p.a) != null);
        const variables = try self.constructorVariables(owner, constructor);
        var substitutions: [32]T.Id = @splat(0);
        try self.match(try self.constructorResult(constructor, depth + 1), p.ty, variables, &substitutions, depth + 1);
        try require((constructor.payload == 0) == (p.b == 0));
        if (p.b != 0) {
            const child = self.m.pattern(p.b);
            try self.match(constructor.payload, child.ty, variables, &substitutions, depth + 1);
            try self.patternMode(p.b, child.ty, bindings, scope, parameters, refutable, depth + 1);
        }
    }
    fn nominalCase(self: *Named, id: core.Id, parameters: []const core.Parameter, closed_rows: T.List, depth: usize) Error!void {
        const input = self.m.matchInputs(id)[0];
        const owner = try nominalOwner(self.m, self.m.types.node(self.m.typeOf(input)), self.remaining);
        const constructors = self.m.nominalConstructors(owner);
        try require(constructors.len <= 4096);
        const arms = self.m.matchArms(id);
        try require(arms.len == constructors.len);
        try self.node(input, parameters, closed_rows, depth + 1);
        var covered: std.bit_set.Static(4096) = .empty;
        for (arms) |arm| {
            try self.step(depth);
            const rows = self.m.armRows(arm);
            try require(arm.guard == 0 and rows.len == 1);
            const patterns = self.m.rowPatterns(rows[0]);
            try require(patterns.len == 1);
            const p = self.m.pattern(patterns[0]);
            try require(p.tag == .constructor and try equal(self.m, p.ty, self.m.typeOf(input), 0, self.remaining));
            const ordinal = std.mem.findScalar(u32, constructors, p.a) orelse return error.InvalidArtifact;
            try require(!covered.isSet(ordinal));
            covered.set(ordinal);
            var bindings: [64]core.BindingId = undefined;
            var scope: Locals = .{ .parent = self.locals };
            self.locals = &scope;
            defer self.locals = scope.parent;
            try self.constructorPattern(patterns[0], &bindings, &scope, parameters, depth + 1);
            try result(self.m, self.m.typeOf(id), self.m.typeOf(arm.body), self.remaining);
            try self.node(arm.body, parameters, closed_rows, depth + 1);
        }
    }
    fn collection(self: *Named, id: core.Id, parameters: []const core.Parameter, closed_rows: T.List, depth: usize) Error!void {
        const n = self.m.node(id);
        const operation = std.enums.fromInt(core.ArrayOp, n.c) orelse return error.InvalidArtifact;
        const arguments = self.m.children(id);
        var inputs: [3]T.Id = undefined;
        try require(arguments.len <= inputs.len);
        for (arguments, inputs[0..arguments.len]) |argument, *input| input.* = self.m.typeOf(argument);
        const Proof = struct {
            reader: *Named,
            closed: T.List,
            pub fn same(proof: @This(), first: T.Id, second: T.Id) Error!void {
                try require(try equal(proof.reader.m, first, second, 0, proof.reader.remaining));
            }
            pub fn callback(proof: @This(), row: T.Effects.Id) Error!void {
                try require(proof.reader.ownedTail(row, proof.closed));
                try require(proof.reader.m.types.rowLabels(row).len == 0);
            }
        };
        try @import("collection_contracts.zig").validate(&self.m.types, operation, inputs[0..arguments.len], n.ty, Proof{ .reader = self, .closed = closed_rows });
        for (arguments) |argument| try self.node(argument, parameters, closed_rows, depth + 1);
    }
    fn nominalField(self: *Named, input: T.Id, output: T.Id, projection: core.Projection, depth: usize) Error!void {
        const original = self.m.types.node(input);
        const owner = try nominalOwner(self.m, original, self.remaining);
        try require(projection.field != 0 and std.meta.eql(projection.nominal, self.m.nominals[owner].identity));
        const constructors = self.m.nominalConstructors(owner);
        const variants = self.m.projection_variants[projection.variants.start..][0..projection.variants.len];
        try require(variants.len == constructors.len);
        for (constructors, variants, 0..) |constructor_index, variant, ordinal| {
            try self.step(depth);
            const constructor = self.m.constructors[constructor_index];
            try require(constructor.tag == ordinal and variant.tag == ordinal);
            const variables = try self.constructorVariables(owner, constructor);
            var bindings: [32]T.Id = @splat(0);
            const result_type = try self.constructorResult(constructor, depth + 1);
            try self.match(result_type, input, variables, &bindings, depth + 1);
            for (bindings[0..variables.len]) |binding| try require(binding != 0);
            const payload = self.m.types.node(constructor.payload);
            try require(payload.tag == .record and variant.field < payload.b);
            const field = self.m.types.recordField(payload, variant.field);
            try require(field.name == projection.field);
            try self.match(field.ty, output, variables, &bindings, depth + 1);
        }
    }
    fn loanCallback(self: *Named, id: core.Id, parameters: []const core.Parameter, closed_rows: T.List, expected: T.Id, depth: usize) Error!void {
        const callback_node = self.m.node(id);
        try require(callback_node.tag == .closure);
        const callback = self.m.closures[callback_node.a];
        const parameter = self.m.types.node(callback.parameter.ty);
        try require(parameter.tag == .usage and (parameter.b == @backingInt(T.UsageKind.borrow) or parameter.b == @backingInt(T.UsageKind.borrow_mut)) and parameter.c != 0);
        const region = self.m.types.node(parameter.c);
        try require(region.tag == .bound and region.a == 0 and region.b == 2 and region.c == callback.parameter.binding);
        var owner: LoanOwner = .{ .region = parameter.c, .parent = self.loan_owner };
        self.loan_owner = &owner;
        defer self.loan_owner = owner.parent;
        try self.node(id, parameters, closed_rows, depth + 1);
        const arrow = try callable(self.m, callback.function_type, self.remaining);
        try result(self.m, expected, arrow.b, self.remaining);
    }
    fn task(self: *Named, id: core.Id, parameters: []const core.Parameter, closed_rows: T.List, depth: usize) Error!void {
        const tasks = @import("task_types.zig");
        try @import("task_core.zig").validateOperationContextWorkspace(self.m, self.units, id, self.remaining, self.workspace);
        const operation: tasks.Op = @fromBackingInt(self.m.node(id).c);
        const operands = self.m.children(id);
        const prior = self.scope_owner;
        defer self.scope_owner = prior;
        if (operation == .scope) {
            const arrow = try callable(self.m, self.m.typeOf(operands[0]), self.remaining);
            const group = self.m.types.node(arrow.a);
            const identity: T.NominalIdentity = .{ .unit = group.b, .decl = group.c };
            try require(identity.decl != 0 and !try self.knownInstance(identity));
            var owner: ScopeOwner = .{ .identity = identity, .parent = prior };
            self.scope_owner = &owner;
            try self.node(operands[0], parameters, closed_rows, depth + 1);
            self.scope_owner = prior;
        } else if (operation == .split) {
            const plan = try @import("task_regions.zig").partition(self.m, id);
            try self.node(operands[0], parameters, closed_rows, depth + 1);
            try self.node(operands[1], parameters, closed_rows, depth + 1);
            const arrow = try callable(self.m, self.m.typeOf(operands[2]), self.remaining);
            const product = self.m.types.node(arrow.a);
            const views = self.m.types.list(.{ .start = product.a, .len = product.b });
            var owners: [16]ScopeOwner = undefined;
            for (views, owners[0..plan.len]) |view, *owner| {
                const info = tasks.viewInfo(&self.m.types, view) orelse return error.InvalidArtifact;
                const scope = self.m.types.node(info.scope);
                owner.* = .{ .identity = .{ .unit = scope.b, .decl = scope.c }, .parent = self.scope_owner, .task_view = info.scope };
                self.scope_owner = owner;
            }
            try self.node(operands[2], parameters, closed_rows, depth + 1);
            self.scope_owner = prior;
        } else {
            for (operands) |operand| try self.node(operand, parameters, closed_rows, depth + 1);
        }
        // No group or partition authority is available after its lexical owner
        // closes. Returned arrows retain their full parameter/result types.
        try self.data(self.m.typeOf(id), depth + 1);
    }
    fn node(self: *Named, id: core.Id, parameters: []const core.Parameter, closed_rows: T.List, depth: usize) Error!void {
        try self.step(depth);
        const saved_rows = self.data_rows;
        const saved_parameters = self.parameters;
        self.data_rows = closed_rows;
        self.parameters = parameters;
        defer self.data_rows = saved_rows;
        defer self.parameters = saved_parameters;
        const n = self.m.node(id);
        if (n.tag == .task) return self.task(id, parameters, closed_rows, depth + 1);
        var row_owner: RowOwner = .{ .closed = closed_rows, .generic = self.row_variables, .parent = self.row_owners };
        if (n.tag == .closure) {
            self.data_rows = self.m.closures[n.a].closed_rows;
            self.row_owners = &row_owner;
        }
        defer self.row_owners = row_owner.parent;
        if (n.tag == .package_pack or n.tag == .package_unpack) {
            return @import("package_core.zig").executableWithBudget(self.m, .{ .units = self.units }, self.remaining);
        }
        if (n.tag == .reference) {
            const reference = self.m.reference(id);
            if (reference.unit == 0 or reference.unit == self.m.unit) {
                for (parameters) |parameter| if (parameter.binding == reference.binding) {
                    try require(try equalWithRows(self.m, parameter.ty, n.ty, self.data_rows, 0, self.remaining));
                    return;
                };
                if (try self.local(reference.binding)) {
                    const binding = self.m.bindings[reference.binding];
                    try require(binding.kind == .local or binding.kind == .parameter);
                    if (!try equalOwnedRows(self.m, binding.ty, n.ty, binding.scheme.closed_rows, self.data_rows, 0, self.remaining)) {
                        // A checked use can widen a callable's latent row. The
                        // ordinary principal proof preserves input variance
                        // and every operation occurrence of its actual owner.
                        var principal: @import("package_contracts.zig").Principal = .{ .left = &self.m.types, .right = &self.m.types, .remaining = self.remaining, .left_rows = binding.scheme.closed_rows, .foreign_views = true };
                        try principal.validate(binding.ty, n.ty);
                    }
                    // Its defining expression/parameter already proved this
                    // exact type, including the callable's own row owner.
                    return;
                }
            }
            const producer = try targetOwner(self.m, self.units, reference, self.workspace);
            if (producer.bindings[reference.binding].kind == .global) {
                if (producer.body(reference.binding)) |body| if (body.is_function) return self.functionValue(id, reference, depth + 1);
            }
        }
        if (n.tag == .operation_value) {
            const operation = self.m.operation_values[n.a];
            try require(try self.knownInstance(operation.instance) and operation.witness == 0 and operation.witness_result == 0);
            try require(try equal(self.m, operation.signature, n.ty, 0, self.remaining));
            const arrow = self.m.types.node(n.ty);
            try require(arrow.tag == .function);
            try self.data(arrow.a, depth + 1);
            try self.data(arrow.b, depth + 1);
            try self.dataRow(arrow.c, depth + 1);
            // An operation value denotes its exact catalog key. Its contextual
            // ambient tail is not an executable callback or a purity proof.
            if (operation.capability != 0) try self.node(operation.capability, parameters, closed_rows, depth + 1);
            return;
        }
        try self.data(n.ty, depth + 1);
        switch (n.tag) {
            .constant => {
                var scalar = self.m.types.node(n.ty);
                if (scalar.tag == .usage) {
                    try require(scalar.c == 0 and (scalar.b == @backingInt(T.UsageKind.unique) or scalar.b == @backingInt(T.UsageKind.shared)));
                    scalar = self.m.types.node(scalar.a);
                }
                const tag = scalar.tag;
                try require(n.b == 0 and n.c == 0 and n.op == .none);
                try require(tag == .unit or tag == .boolean or tag == .u32 or tag == .f32);
                if (tag == .unit) try require(n.a == 0);
                if (tag == .boolean) try require(n.a <= 1);
            },
            .panic => try require(n.ty == T.never),
            .reference => {
                const ref = self.m.reference(id);
                if (ref.unit != 0 and ref.unit != self.m.unit) return self.foreignData(id, ref, depth + 1);
                const binding = self.m.bindings[ref.binding];
                try require(binding.kind == .global);
                const body = self.m.body(ref.binding) orelse return error.InvalidArtifact;
                if (body.is_function) return self.functionValue(id, ref, depth + 1);
                try require(body.parameters.len == 0);
                const variables = try self.binders(body);
                var bindings: [32]T.Id = @splat(0);
                try self.match(binding.ty, n.ty, variables, &bindings, depth + 1);
                try require(self.m.typeOf(body.root) == T.never or try equal(self.m, binding.ty, self.m.typeOf(body.root), 0, self.remaining));
                const caller_variables = self.variables;
                const caller_locals = self.locals;
                const caller_loop = self.loop_owner;
                const caller_rows = self.row_variables;
                const caller_row_owners = self.row_owners;
                const caller_loan = self.loan_owner;
                self.variables = variables;
                self.row_variables = body.scheme.row_variables;
                self.locals = null;
                self.loop_owner = null;
                self.row_owners = null;
                self.loan_owner = null;
                defer self.variables = caller_variables;
                defer self.row_variables = caller_rows;
                defer self.locals = caller_locals;
                defer self.loop_owner = caller_loop;
                defer self.row_owners = caller_row_owners;
                defer self.loan_owner = caller_loan;
                try self.node(body.root, &.{}, body.closed_rows, depth + 1);
                var effects: Effects = .{ .workspace = self.workspace, .m = self.m, .units = self.units, .target_module = self.m, .target = self.m.types.row(0), .closed_rows = body.closed_rows, .remaining = self.remaining, .checked_calls = true, .variables = variables, .row_owners = self.row_owners };
                try effects.visit(body.root, depth + 1);
            },
            .type_constructor => try require(n.a == 0 and n.b == 0 and n.c == 0 and self.m.types.node(n.ty).tag == .type_constructor),
            .resolver_op => {
                try resolverShape(self.m, id);
                const metadata = self.m.resolverInfo(id);
                try self.node(metadata.resolver, parameters, closed_rows, depth + 1);
                const arguments = self.m.resolverArguments(id);
                const prior_callback = self.resolver_callback;
                defer self.resolver_callback = prior_callback;
                if (metadata.operation == .bind or metadata.operation == .iterate) self.resolver_callback = arguments[1];
                switch (metadata.operation) {
                    .monad => {},
                    .forward => try require(try equal(self.m, n.ty, self.m.typeOf(arguments[0]), 0, self.remaining)),
                    .run => {
                        const action = try callable(self.m, self.m.typeOf(arguments[0]), self.remaining);
                        try require(action.a == T.unit and try equal(self.m, action.b, n.ty, 0, self.remaining));
                    },
                    .pure, .bind, .iterate => {
                        _ = try self.call(id, closed_rows, depth + 1);
                    },
                }
                if (metadata.operation == .monad or metadata.operation == .run or metadata.operation == .forward)
                    for (arguments) |argument| try self.node(argument, parameters, closed_rows, depth + 1);
            },
            .call => _ = try self.call(id, closed_rows, depth + 1),
            .apply => {
                const callee = self.m.node(n.a);
                if (callee.tag != .operation_value) {
                    const arrow = try callable(self.m, callee.ty, self.remaining);
                    try require(n.c == 0);
                    try require(try equal(self.m, arrow.a, self.m.typeOf(n.b), 0, self.remaining) and try equal(self.m, arrow.b, n.ty, 0, self.remaining));
                    const parent_callback = self.resolver_callback;
                    if (callee.tag == .closure) self.resolver_callback = n.a;
                    self.node(n.a, parameters, closed_rows, depth + 1) catch |err| {
                        self.resolver_callback = parent_callback;
                        return err;
                    };
                    self.resolver_callback = parent_callback;
                    return self.node(n.b, parameters, closed_rows, depth + 1);
                }
                try require(callee.tag == .operation_value);
                const operation = self.m.operation_values[callee.a];
                try require(try self.knownInstance(operation.instance));
                try require(operation.witness == 0 and operation.witness_result == 0);
                const arrow = self.m.types.node(operation.signature);
                try require(arrow.tag == .function and try equal(self.m, operation.signature, callee.ty, 0, self.remaining));
                try require(try equal(self.m, arrow.a, self.m.typeOf(n.b), 0, self.remaining) and try equal(self.m, arrow.b, n.ty, 0, self.remaining));
                const labels = self.m.types.rowLabels(arrow.c);
                const actual = self.m.types.list(operation.arguments);
                try self.dataRow(arrow.c, depth + 1);
                var found = false;
                for (labels) |id_| {
                    const label = self.m.types.operations[id_];
                    if (!std.meta.eql(label.identity, operation.identity) or !std.meta.eql(label.instance, operation.instance)) continue;
                    const expected = self.m.types.list(label.arguments);
                    if (expected.len != actual.len) continue;
                    var matched = true;
                    for (expected, actual) |left, right| if (!try equal(self.m, left, right, 0, self.remaining)) {
                        matched = false;
                    };
                    if (matched) found = true;
                }
                try require(found);
                if (operation.capability != 0) try self.node(operation.capability, parameters, closed_rows, depth + 1);
                try self.node(n.b, parameters, closed_rows, depth + 1);
            },
            .computation => {
                const shape = self.m.types.node(n.ty);
                try require(shape.tag == .nominal and shape.a == std.math.maxInt(u32) and shape.b == 5);
                const parts = self.m.types.nominalArguments(shape);
                try require(parts.len == 1 and n.b == 0 and n.c == 0 and try equal(self.m, parts[0], self.m.typeOf(n.a), 0, self.remaining));
                try self.node(n.a, parameters, closed_rows, depth + 1);
            },
            .request_decision => try self.decision(id, parameters, closed_rows, depth + 1),
            .effect_provider => {
                try require(self.m.types.node(n.ty).tag == .provider);
                try self.node(n.a, parameters, closed_rows, depth + 1);
                try self.node(n.b, parameters, closed_rows, depth + 1);
            },
            .state_provider => {
                try require(self.m.types.node(n.ty).tag == .state_provider);
                try self.node(n.a, parameters, closed_rows, depth + 1);
                try self.node(n.b, parameters, closed_rows, depth + 1);
                try self.node(n.c, parameters, closed_rows, depth + 1);
            },
            .handle => {
                try self.node(n.a, parameters, closed_rows, depth + 1);
                try self.node(n.b, parameters, closed_rows, depth + 1);
            },
            .usage_read, .usage_share => try self.node(n.a, parameters, closed_rows, depth + 1),
            .usage_borrow => {
                try self.node(n.a, parameters, closed_rows, depth + 1);
                try self.loanCallback(n.b, parameters, closed_rows, n.ty, depth + 1);
            },
            .resource_acquire, .resource_scope => {
                try self.node(n.a, parameters, closed_rows, depth + 1);
                try self.node(n.b, parameters, closed_rows, depth + 1);
                if (n.tag == .resource_scope) try self.loanCallback(n.c, parameters, closed_rows, n.ty, depth + 1);
            },
            .resource_release => try self.node(n.a, parameters, closed_rows, depth + 1),
            .effect_scope => {
                const callback_node = self.m.node(n.a);
                try require(callback_node.tag == .closure);
                const callback = self.m.closures[callback_node.a];
                const capability = self.m.types.node(callback.parameter.ty);
                try require(capability.tag == .scoped and capability.c != 0);
                const identity: T.NominalIdentity = .{ .unit = capability.b, .decl = capability.c };
                try require(!try self.knownInstance(identity));
                var scope: ScopeOwner = .{ .identity = identity, .parent = self.scope_owner };
                self.scope_owner = &scope;
                defer self.scope_owner = scope.parent;
                try self.node(n.a, parameters, closed_rows, depth + 1);
                const arrow = self.m.types.node(callback.function_type);
                try require(arrow.tag == .function);
                try result(self.m, n.ty, arrow.b, self.remaining);
            },
            .closure => {
                const callback_owner = self.resolver_callback;
                defer self.resolver_callback = callback_owner;
                const prior_decision = self.decision_owner;
                if (prior_decision) |owner| if (owner.callback != id) {
                    self.decision_owner = null;
                };
                defer self.decision_owner = prior_decision;
                const closure = self.m.closures[n.a];
                try require(n.b == 0 and n.c == 0 and try equalWithRows(self.m, closure.function_type, n.ty, closure.closed_rows, 0, self.remaining));
                if (closure.qualifier != 0) {
                    const owner = self.m.bindings[closure.qualifier];
                    try require(owner.kind == .local and owner.initializer == id);
                    try require(owner.scheme.variables.len == 0 and owner.scheme.row_variables.len == 0 and owner.scheme.obligations.len == 0 and owner.scheme.generative.len == 0);
                    try require(try equalWithRows(self.m, owner.ty, n.ty, closure.closed_rows, 0, self.remaining));
                    try require(owner.scheme.root != 0 and try equalWithRows(self.m, owner.scheme.root, n.ty, closure.closed_rows, 0, self.remaining));
                }
                const arrow = try callable(self.m, n.ty, self.remaining);
                const prior_ambient = self.ambient;
                self.ambient = self.m.types.row(arrow.c);
                defer self.ambient = prior_ambient;
                try require(try equal(self.m, arrow.a, closure.parameter.ty, 0, self.remaining));
                if (closure.parameter.binding == 0) {
                    try require(arrow.a == T.unit);
                } else {
                    const parameter = self.m.bindings[closure.parameter.binding];
                    try require(parameter.kind == .parameter or (parameter.kind == .local and self.resolver_callback == id));
                    try require(try equal(self.m, parameter.ty, arrow.a, 0, self.remaining));
                }
                try result(self.m, arrow.b, self.m.typeOf(closure.body), self.remaining);
                const captures = self.m.extra[closure.captures.start..][0..closure.captures.len];
                try require(captures.len <= 64);
                for (captures, 0..) |capture, index| {
                    try require(capture != closure.parameter.binding and std.mem.findScalar(core.BindingId, captures[0..index], capture) == null);
                    var found = try self.local(capture);
                    for (parameters) |outer| if (outer.binding == capture) {
                        found = true;
                    };
                    try require(found);
                }
                var scope: Locals = .{ .bindings = captures, .parent = null };
                const parent = self.locals;
                const parent_loop = self.loop_owner;
                self.locals = &scope;
                self.loop_owner = null;
                defer self.locals = parent;
                defer self.loop_owner = parent_loop;
                self.resolver_callback = 0;
                const parent_parameters = self.parameters;
                self.parameters = (&closure.parameter)[0..1];
                defer self.parameters = parent_parameters;
                try self.node(closure.body, &.{closure.parameter}, closure.closed_rows, depth + 1);
                var effects: Effects = .{ .workspace = self.workspace, .ambient = self.ambient, .m = self.m, .units = self.units, .target_module = self.m, .target = self.m.types.row(arrow.c), .closed_rows = closure.closed_rows, .remaining = self.remaining, .checked_calls = true, .variables = self.variables, .row_owners = self.row_owners };
                try require(effects.target.labels.len <= effects.seen.len);
                try effects.visit(closure.body, depth + 1);
            },
            .construct => {
                const constructor = self.m.constructors[n.a];
                const owner = try nominalOwner(self.m, self.m.types.node(n.ty), self.remaining);
                try require(constructor.nominal == owner and std.mem.findScalar(u32, self.m.nominalConstructors(owner), n.a) != null);
                const variables = self.m.types.list(constructor.scheme.variables);
                var bindings: [32]T.Id = @splat(0);
                const output = try self.constructorResult(constructor, depth + 1);
                try self.match(output, n.ty, variables, &bindings, depth + 1);
                for (bindings[0..variables.len]) |binding| try require(binding != 0);
                try require((constructor.payload == 0) == (n.b == 0));
                if (n.b != 0) {
                    var expected = constructor.payload;
                    if (n.c != 0) {
                        try require(n.c == 1 and self.m.types.node(constructor.payload).tag == .record);
                        expected = self.m.types.node(constructor.scheme.root).a;
                    }
                    try self.match(expected, self.m.typeOf(n.b), variables, &bindings, depth + 1);
                    try self.node(n.b, parameters, closed_rows, depth + 1);
                } else try require(n.c == 0);
            },
            .type_same => {
                try require(n.ty == T.boolean and n.c == 0);
                try self.node(n.a, parameters, closed_rows, depth + 1);
                try self.node(n.b, parameters, closed_rows, depth + 1);
            },
            .scalar, .logical => {
                try require(n.c == 0);
                const left = self.m.typeOf(n.a);
                const tag = self.m.types.node(left).tag;
                if (n.tag == .logical) try require(tag == .boolean);
                switch (n.op) {
                    .equal, .not_equal => try require(tag == .u32 or tag == .f32 or tag == .boolean),
                    .add, .sub, .mul, .div, .less, .less_equal, .greater, .greater_equal, .neg => try require(tag == .u32 or tag == .f32),
                    .rem, .bit_and, .bit_or, .bit_xor, .shift_left, .shift_right, .convert_u32_f32 => try require(tag == .u32),
                    .abs, .ceil, .floor, .trunc, .sqrt, .convert_f32_u32 => try require(tag == .f32),
                    .and_, .or_ => try require(tag == .boolean),
                    .none, .continue_, .shift_right_signed, .min, .max, .bit_not, .bit_andnot, .any_true, .all_true, .select, .shuffle, .swizzle, .broadcast, .bits, .from_bits, .relaxed_madd, .relaxed_nmadd, .convert_i32_f32, .convert_f32_i32 => return error.InvalidArtifact,
                }
                if (n.b != 0) try require(try equal(self.m, left, self.m.typeOf(n.b), 0, self.remaining));
                const expected: T.Id = switch (n.op) {
                    .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .and_, .or_ => T.boolean,
                    .convert_u32_f32 => T.f32_type,
                    .convert_f32_u32 => T.u32_type,
                    else => left,
                };
                try require(try equal(self.m, expected, n.ty, 0, self.remaining));
                if (n.a != 0) try self.node(n.a, parameters, closed_rows, depth + 1);
                if (n.b != 0) try self.node(n.b, parameters, closed_rows, depth + 1);
            },
            .match => try self.booleanCase(id, parameters, closed_rows, depth + 1),
            .if_value => {
                try require(self.m.typeOf(n.a) == T.boolean);
                try require(self.m.typeOf(n.b) == T.never or try equal(self.m, n.ty, self.m.typeOf(n.b), 0, self.remaining));
                try require(self.m.typeOf(n.c) == T.never or try equal(self.m, n.ty, self.m.typeOf(n.c), 0, self.remaining));
                try self.node(n.a, parameters, closed_rows, depth + 1);
                try self.node(n.b, parameters, closed_rows, depth + 1);
                try self.node(n.c, parameters, closed_rows, depth + 1);
            },
            .product, .record, .array => {
                const shape = self.m.types.node(n.ty);
                const children = self.m.children(id);
                try require((n.tag == .product and shape.tag == .product) or (n.tag == .record and shape.tag == .record) or (n.tag == .array and shape.tag == .array));
                if (n.tag != .array) try require(children.len == shape.b);
                for (children, 0..) |child, index| {
                    const expected = switch (n.tag) {
                        .product => self.m.types.list(.{ .start = shape.a, .len = shape.b })[index],
                        .record => self.m.types.recordField(shape, self.m.extra[n.c + index]).ty,
                        .array => shape.a,
                        else => unreachable,
                    };
                    try require(self.m.typeOf(child) == T.never or try equal(self.m, expected, self.m.typeOf(child), 0, self.remaining));
                    try self.node(child, parameters, closed_rows, depth + 1);
                }
            },
            .project => {
                const projection = self.m.projections[n.b];
                const input = self.m.typeOf(n.a);
                try require(try equal(self.m, input, projection.source_type, 0, self.remaining));
                try require(try equal(self.m, n.ty, projection.result_type, 0, self.remaining));
                const shape = self.m.types.node(input);
                var actual: T.Id = 0;
                if (shape.tag == .nominal) {
                    try self.nominalField(input, n.ty, projection, depth + 1);
                    actual = n.ty;
                } else if (shape.tag == .record and projection.field != 0) {
                    for (0..shape.b) |index| {
                        const field = self.m.types.recordField(shape, index);
                        if (field.name == projection.field) actual = field.ty;
                    }
                } else if (shape.tag == .product and projection.field == 0) {
                    try require(projection.variants.len == 1);
                    const variant = self.m.projection_variants[projection.variants.start];
                    try require(variant.tag == 0 and variant.field < shape.b);
                    actual = self.m.types.list(.{ .start = shape.a, .len = shape.b })[variant.field];
                }
                try require(actual != 0 and try equal(self.m, n.ty, actual, 0, self.remaining));
                try self.node(n.a, parameters, closed_rows, depth + 1);
            },
            .array_op => try self.collection(id, parameters, closed_rows, depth + 1),
            .block => try self.block(id, parameters, closed_rows, depth + 1),
            .staging => {
                // A lifted or spliced operand runs one stage earlier than this
                // later-stage call. Its stage depth, liftable shape and effects
                // are proved by stagingScopes, the module-wide staging pass and
                // Effects; this proof owns only the later-stage value shape.
                const op: staging.Op = @fromBackingInt(n.c);
                try require(op == .lift or op == .splice);
            },
            // Other executable forms need their own complete semantic proof;
            // bounds and a selected type do not supply executable authority.
            else => return error.InvalidArtifact,
        }
    }
};
// A task call uses the same declaration/instance/effect proof as a staged
// call. Its caller authority comes only from actual lexical owner nodes.
const TaskCallSite = struct {
    proof: *Named,
    target: core.Id,
    reference: bool,
    rows: T.List,
    body: *const core.Body,
    found: bool = false,
    fn visit(self: *TaskCallSite, id: core.Id, depth: usize) Error!void {
        if (id == 0) return;
        try self.proof.step(depth);
        const m = self.proof.m;
        const n = m.node(id);
        if (id == self.target) {
            self.proof.variables = try self.proof.binders(self.body);
            if (self.reference) try self.proof.node(id, self.proof.parameters, self.rows, depth + 1) else _ = try self.proof.call(id, self.rows, depth + 1);
            self.found = true;
            return;
        }
        if (n.tag == .closure or n.tag == .suspend_) {
            const closure = &m.closures[n.a];
            const parent_ambient = self.proof.ambient;
            self.proof.ambient = m.types.row((try callable(m, closure.function_type, self.proof.remaining)).c);
            defer self.proof.ambient = parent_ambient;
            const parent_parameters = self.proof.parameters;
            const parent_rows = self.rows;
            const parent_locals = self.proof.locals;
            const parent_row_owners = self.proof.row_owners;
            var locals: Named.Locals = .{ .parameters = parent_parameters, .parent = parent_locals };
            var rows: Named.RowOwner = .{ .closed = parent_rows, .generic = self.proof.row_variables, .parent = parent_row_owners };
            self.proof.locals = &locals;
            self.proof.row_owners = &rows;
            self.proof.parameters = (&closure.parameter)[0..1];
            self.rows = closure.closed_rows;
            defer self.proof.locals = parent_locals;
            defer self.proof.row_owners = parent_row_owners;
            defer self.proof.parameters = parent_parameters;
            defer self.rows = parent_rows;
            return self.visit(closure.body, depth + 1);
        }
        if (n.tag == .block or n.tag == .suite) {
            var bindings: [4096]core.BindingId = undefined;
            var locals: Named.Locals = .{ .parent = self.proof.locals };
            self.proof.locals = &locals;
            defer self.proof.locals = locals.parent;
            for (m.children(id)) |child| {
                try self.visit(child, depth + 1);
                const definition = m.node(child);
                if (definition.tag == .bind) {
                    try require(locals.bindings.len < bindings.len);
                    bindings[locals.bindings.len] = definition.a;
                    locals.bindings = bindings[0 .. locals.bindings.len + 1];
                } else if (definition.tag == .pattern_bind) {
                    try self.proof.patternMode(definition.a, m.typeOf(definition.b), &bindings, &locals, self.proof.parameters, definition.c != 0, depth + 1);
                }
            }
            return;
        }
        if (n.tag == .effect_scope or (n.tag == .task and n.c == @backingInt(@import("task_types.zig").Op.scope))) {
            var callback = n.a;
            if (n.tag == .task) callback = m.children(id)[0];
            const scope = m.types.node(m.closure(callback).parameter.ty);
            try require(scope.tag == .scoped and scope.c != 0);
            var owner: Named.ScopeOwner = .{ .identity = .{ .unit = scope.b, .decl = scope.c }, .parent = self.proof.scope_owner };
            self.proof.scope_owner = &owner;
            defer self.proof.scope_owner = owner.parent;
            return self.visit(callback, depth + 1);
        }
        if (n.tag == .task and n.c == @backingInt(@import("task_types.zig").Op.split)) {
            const plan = try @import("task_regions.zig").partition(m, id);
            const operands = m.children(id);
            try self.visit(operands[0], depth + 1);
            try self.visit(operands[1], depth + 1);
            const product = m.types.node(m.closure(operands[2]).parameter.ty);
            const views = m.types.list(.{ .start = product.a, .len = product.b });
            var owners: [16]Named.ScopeOwner = undefined;
            const parent = self.proof.scope_owner;
            defer self.proof.scope_owner = parent;
            for (views, owners[0..plan.len]) |view, *owner| {
                const info = @import("task_types.zig").viewInfo(&m.types, view) orelse return error.InvalidArtifact;
                const scope = m.types.node(info.scope);
                owner.* = .{ .identity = .{ .unit = scope.b, .decl = scope.c }, .parent = self.proof.scope_owner, .task_view = info.scope };
                self.proof.scope_owner = owner;
            }
            return self.visit(operands[2], depth + 1);
        }
        if (n.tag == .usage_borrow or n.tag == .resource_scope) {
            try self.visit(n.a, depth + 1);
            var callback = n.b;
            if (n.tag == .resource_scope) {
                try self.visit(n.b, depth + 1);
                callback = n.c;
            }
            const closure = m.closure(callback);
            const loan = m.types.node(closure.parameter.ty);
            try require(loan.tag == .usage and loan.c != 0);
            const region = m.types.node(loan.c);
            try require(region.tag == .bound and region.a == 0 and region.b == 2 and region.c == closure.parameter.binding);
            var owner: Named.LoanOwner = .{ .region = loan.c, .parent = self.proof.loan_owner };
            self.proof.loan_owner = &owner;
            defer self.proof.loan_owner = owner.parent;
            return self.visit(callback, depth + 1);
        }
        if (n.tag == .staging and n.c == @backingInt(staging.Op.quote)) {
            const ambient = self.proof.ambient;
            self.proof.ambient = null;
            defer self.proof.ambient = ambient;
            const scope = self.proof.scope_owner;
            const loan = self.proof.loan_owner;
            self.proof.scope_owner = null;
            self.proof.loan_owner = null;
            defer self.proof.scope_owner = scope;
            defer self.proof.loan_owner = loan;
            return self.visit(n.a, depth + 1);
        }
        const Visitor = struct {
            site: *TaskCallSite,
            depth: usize,
            pub fn append(visitor: *@This(), _: std.mem.Allocator, child: core.Id) error{PlanLimit}!void {
                visitor.site.visit(child, visitor.depth) catch return error.PlanLimit;
            }
            pub fn appendSlice(visitor: *@This(), allocator: std.mem.Allocator, children: []const core.Id) error{PlanLimit}!void {
                for (children) |child| try visitor.append(allocator, child);
            }
        };
        var visitor: Visitor = .{ .site = self, .depth = depth + 1 };
        @import("../eval/body_recipe.zig").appendChildren(&visitor, std.heap.page_allocator, m, id, false) catch return error.InvalidArtifact;
    }
};
pub fn taskNamedContext(m: *const core.Module, units: []const *const core.Module, id: core.Id, reference: bool, remaining: *usize) Error!void {
    return taskNamedContextWorkspace(m, units, id, reference, remaining, null);
}
pub fn taskNamedContextWorkspace(m: *const core.Module, units: []const *const core.Module, id: core.Id, reference: bool, remaining: *usize, workspace: ?*@import("scheme_equations.zig").Workspace) Error!void {
    var found = false;
    for (m.bodies) |*body| {
        if (body.root == 0) continue;
        var proof: Named = .{ .workspace = workspace, .m = m, .units = units, .remaining = remaining, .current_scheme = body.scheme, .parameters = m.bodyParameters(body), .row_variables = body.scheme.row_variables };
        var signature = m.bindings[body.binding].ty;
        for (m.bodyParameters(body)) |_| {
            var arrow = m.types.node(signature);
            if (arrow.tag == .usage) arrow = m.types.node(arrow.a);
            if (arrow.tag != .function) break;
            proof.ambient = m.types.row(arrow.c);
            signature = arrow.b;
        }
        var site: TaskCallSite = .{ .proof = &proof, .target = id, .reference = reference, .rows = body.closed_rows, .body = body };
        try site.visit(body.root, 0);
        found = found or site.found;
    }
    try require(found);
}
pub fn namedCall(m: *const core.Module, id: core.Id, remaining: *usize) Error!*const core.Body {
    return namedCallContext(m, &.{}, id, remaining);
}
pub fn namedReferenceContext(m: *const core.Module, units: []const *const core.Module, id: core.Id, closed_rows: T.List, remaining: *usize) Error!void {
    return namedReferenceContextWorkspace(m, units, id, closed_rows, remaining, null);
}
pub fn namedReferenceContextWorkspace(m: *const core.Module, units: []const *const core.Module, id: core.Id, closed_rows: T.List, remaining: *usize, workspace: ?*@import("scheme_equations.zig").Workspace) Error!void {
    var proof: Named = .{ .workspace = workspace, .m = m, .units = units, .remaining = remaining };
    try proof.node(id, &.{}, closed_rows, 0);
}
pub fn namedCallContext(m: *const core.Module, units: []const *const core.Module, id: core.Id, remaining: *usize) Error!*const core.Body {
    return namedCallContextWorkspace(m, units, id, remaining, null);
}
pub fn namedCallContextWorkspace(m: *const core.Module, units: []const *const core.Module, id: core.Id, remaining: *usize, workspace: ?*@import("scheme_equations.zig").Workspace) Error!*const core.Body {
    try taskNamedContextWorkspace(m, units, id, false, remaining, workspace);
    const call_ = try executableCall(m, units, id, remaining, workspace);
    const producer = try targetOwner(m, units, call_.target, workspace);
    return producer.body(call_.target.binding) orelse error.InvalidArtifact;
}
fn targetOwner(m: *const core.Module, units: []const *const core.Module, target: core.BindingRef, workspace: ?*@import("scheme_equations.zig").Workspace) Error!*const core.Module {
    if (target.unit == 0 or target.unit == m.unit) {
        try require(target.binding < m.bindings.len);
        return m;
    }
    var found: ?*const core.Module = null;
    for (units) |candidate| {
        if (candidate.unit != target.unit) continue;
        try require(found == null and target.binding < candidate.bindings.len);
        // Siblings may not have reached their enclosing bundle's bounds pass.
        // No body, type, list or operation edge can be followed before this.
        try @import("scheme_equations.zig").bounds(workspace, candidate, .{ .units = units });
        found = candidate;
    }
    return found orelse error.InvalidArtifact;
}
pub fn declaredOperation(m: *const core.Module, units: []const *const core.Module, operation: T.Operation, input: T.Id, output: T.Id, remaining: *usize) Error!void {
    var producer = m;
    if (operation.identity.unit != 0 and operation.identity.unit != m.unit) {
        var found: ?*const core.Module = null;
        for (units) |owner| {
            try require(remaining.* != 0);
            remaining.* -= 1;
            if (owner.unit != operation.identity.unit) continue;
            try require(found == null);
            try @import("frozen_core_validation.zig").validateBounds(owner, .{ .units = units });
            found = owner;
        }
        producer = found orelse return error.InvalidArtifact;
    }
    return declaredOperationIn(m, producer, operation, input, output, remaining);
}
pub fn declaredOperationIn(m: *const core.Module, producer: *const core.Module, operation: T.Operation, input: T.Id, output: T.Id, remaining: *usize) Error!void {
    const arguments = m.types.list(operation.arguments);
    var found = false;
    for (producer.operation_names) |header| {
        try require(remaining.* != 0);
        remaining.* -= 1;
        if (!cross.sameIdentity(producer, header.identity, m, operation.identity)) continue;
        try require(header.parameter != 0 and header.result != 0);
        const parameters = producer.types.list(header.parameters);
        const variables = producer.types.list(header.variables);
        try require(parameters.len == arguments.len and variables.len <= 32);
        var substitutions: [32]T.Id = @splat(0);
        for (parameters, arguments) |formal, actual| try cross.match(producer, formal, m, actual, variables, &substitutions, remaining, 0);
        try cross.match(producer, header.parameter, m, input, variables, &substitutions, remaining, 0);
        try cross.match(producer, header.result, m, output, variables, &substitutions, remaining, 0);
        for (substitutions[0..variables.len]) |binding| try require(binding != 0);
        found = true;
    }
    try require(found);
}
const resolver_core = @import("resolver_core.zig");
const resolverShape = resolver_core.shape;
const executableCall = resolver_core.callWorkspace;
const Effects = struct {
    workspace: ?*@import("scheme_equations.zig").Workspace = null,
    m: *const core.Module,
    units: []const *const core.Module = &.{},
    target_module: *const core.Module,
    target: T.Effects.Row,
    closed_rows: T.List,
    seen: [256]bool = @splat(false),
    remaining: *usize,
    arguments_stack: [128]struct { binding: core.BindingId, node: core.Id } = undefined,
    arguments_len: usize = 0,
    // Named's structural walk already reconstructed every nested call. Reuse
    // that proof while observing effects, avoiding exponential reproving.
    checked_calls: bool = false,
    variables: []const T.Id = &.{},
    handlers: ?*const Handler = null,
    ambient: ?T.Effects.Row = null,
    row_owners: ?*const Named.RowOwner = null,
    const Handler = struct { operations: []const T.Operation = &.{}, parent: ?*const Handler };
    fn sameOperation(self: *Effects, left: T.Operation, right: T.Operation) Error!bool {
        if (!std.meta.eql(left.identity, right.identity) or !std.meta.eql(left.instance, right.instance)) return false;
        const first = self.m.types.list(left.arguments);
        const second = self.m.types.list(right.arguments);
        if (first.len != second.len) return false;
        for (first, second) |a, b| if (!try equal(self.m, a, b, 0, self.remaining)) return false;
        return true;
    }
    fn consumeOperation(self: *Effects, actual: T.Operation) Error!void {
        var handler = self.handlers;
        while (handler) |current| : (handler = current.parent) {
            try require(self.remaining.* != 0);
            self.remaining.* -= 1;
            for (current.operations) |operation| if (try self.sameOperation(actual, operation)) return;
        }
        try self.consumeTarget(actual, null);
    }
    fn consumeTarget(self: *Effects, actual: T.Operation, used: ?*[256]bool) Error!void {
        const expected = self.target_module.types.effects.labels[self.target.labels.start..][0..self.target.labels.len];
        var matched = false;
        for (expected, 0..) |candidate, index| {
            if (used) |slots| if (slots[index]) continue;
            const wanted = self.target_module.types.operations[candidate];
            if (!cross.sameIdentity(self.m, actual.identity, self.target_module, wanted.identity) or !cross.sameIdentity(self.m, actual.instance, self.target_module, wanted.instance) or actual.arguments.len != wanted.arguments.len) continue;
            var same = true;
            for (self.m.types.list(actual.arguments), self.target_module.types.list(wanted.arguments)) |left, right| {
                cross.match(self.m, left, self.target_module, right, &.{}, &.{}, self.remaining, 0) catch {
                    same = false;
                };
            }
            if (!same) continue;
            self.seen[index] = true;
            matched = true;
            if (used) |slots| {
                slots[index] = true;
                return;
            }
        }
        try require(matched);
    }
    fn consume(self: *Effects, row_id: T.Effects.Id) Error!void {
        const row = self.m.types.effects.node(row_id);
        try self.consumeLabels(row);
        if (row.tail != .closed) {
            var closed = false;
            if (row.tail == .variable) closed = std.mem.findScalar(u32, self.m.types.list(self.closed_rows), row.tail.variable) != null;
            if (row.tail == .variable) {
                var owner = self.row_owners;
                while (owner) |current| : (owner = current.parent) {
                    try require(self.remaining.* != 0);
                    self.remaining.* -= 1;
                    if (std.mem.findScalar(u32, self.m.types.list(current.closed), row.tail.variable) != null) closed = true;
                }
            }
            try require(closed or std.meta.eql(row.tail, self.target.tail));
        }
    }
    fn consumeLabels(self: *Effects, row: T.Effects.Row) Error!void {
        var used: [256]bool = @splat(false);
        var supplied: [256]struct { handler: *const Handler, index: usize } = undefined;
        var supplied_count: usize = 0;
        for (self.m.types.effects.labels[row.labels.start..][0..row.labels.len]) |label| {
            const actual = self.m.types.operations[label];
            var handled = false;
            var handler = self.handlers;
            while (handler) |current| : (handler = current.parent) {
                try require(self.remaining.* != 0);
                self.remaining.* -= 1;
                for (current.operations, 0..) |operation, index| {
                    var already_used = false;
                    for (supplied[0..supplied_count]) |slot| if (slot.handler == current and slot.index == index) {
                        already_used = true;
                    };
                    if (already_used or !try self.sameOperation(actual, operation)) continue;
                    try require(supplied_count < supplied.len);
                    supplied[supplied_count] = .{ .handler = current, .index = index };
                    supplied_count += 1;
                    handled = true;
                    break;
                }
                if (handled) break;
            }
            if (!handled) try self.consumeTarget(actual, &used);
        }
    }
    fn resolve(self: *Effects, source: core.Id) Error!core.Id {
        var id = source;
        for (0..128) |_| {
            const node = self.m.node(id);
            if (node.tag != .reference) return id;
            const target = self.m.reference(id);
            if (target.unit != 0 and target.unit != self.m.unit) {
                const producer = try targetOwner(self.m, self.units, target, self.workspace);
                const body = producer.body(target.binding) orelse return error.InvalidArtifact;
                try require(producer.binding(target.binding).kind == .global and body.is_function);
                return id;
            }
            if (self.m.body(target.binding)) |body| if (body.is_function) return id;
            var actual: core.Id = 0;
            for (self.arguments_stack[0..self.arguments_len]) |argument| if (argument.binding == target.binding) {
                actual = argument.node;
            };
            if (actual == 0) actual = self.m.bindings[target.binding].initializer;
            if (actual == 0) {
                const binding = self.m.bindings[target.binding];
                try require(binding.kind == .parameter or binding.kind == .local);
                return id;
            }
            id = actual;
        }
        return error.InvalidArtifact;
    }
    fn arguments(self: *Effects, ids: []const core.Id, depth: usize) Error!void {
        for (ids) |id| try self.visit(id, depth + 1);
    }
    fn providerOperation(self: *Effects, id: core.Id, token_id: T.Id, depth: usize) Error!T.Operation {
        const operation_node = self.m.node(try self.resolve(id));
        try require(operation_node.tag == .operation_value);
        const metadata = self.m.operation_values[operation_node.a];
        try require(try equalWithRows(self.m, operation_node.ty, metadata.signature, self.closed_rows, 0, self.remaining));
        var token = self.m.types.node(token_id);
        var instance: T.NominalIdentity = .{ .unit = 0, .decl = 0 };
        if (token.tag == .scoped) {
            instance = .{ .unit = token.b, .decl = token.c };
            token = self.m.types.node(token.a);
        }
        try require(token.tag == .nominal and metadata.identity.unit == token.a and metadata.identity.decl == token.b and std.meta.eql(metadata.instance, instance));
        const first = self.m.types.nominalArguments(token);
        const second = self.m.types.list(metadata.arguments);
        try require(first.len == second.len);
        for (first, second) |a, b| try require(try equal(self.m, a, b, 0, self.remaining));
        try self.visit(id, depth + 1);
        return .{ .identity = metadata.identity, .instance = metadata.instance, .arguments = metadata.arguments };
    }
    fn handlerRows(self: *Effects, id: core.Id, handler: *const Handler, shape: T.Node) Error!void {
        const evidence = self.m.handleEffects(id) orelse return;
        try require(evidence.node == id and try equal(self.m, evidence.first, shape.a, 0, self.remaining));
        if (handler.operations.len == 2) {
            try require(evidence.second != 0 and try equal(self.m, evidence.second, shape.b, 0, self.remaining));
        } else try require(evidence.second == 0);
        const extended = self.m.types.row(evidence.extended);
        const residual = self.m.types.row(evidence.residual);
        const first = self.m.types.rowLabels(evidence.extended);
        const second = self.m.types.rowLabels(evidence.residual);
        try require(first.len <= 256 and first.len == second.len + handler.operations.len);
        var used: [256]bool = @splat(false);
        for (handler.operations) |operation| {
            var matched = false;
            for (first, 0..) |label, index| {
                if (used[index] or !try self.sameOperation(operation, self.m.types.operations[label])) continue;
                used[index] = true;
                matched = true;
                break;
            }
            try require(matched);
        }
        for (second) |label| {
            var matched = false;
            for (first, 0..) |candidate, index| {
                if (used[index] or !try self.sameOperation(self.m.types.operations[label], self.m.types.operations[candidate])) continue;
                used[index] = true;
                matched = true;
                break;
            }
            try require(matched);
        }
        var first_tail = extended.tail;
        var second_tail = residual.tail;
        const closed = self.m.types.list(self.closed_rows);
        if (first_tail == .variable and std.mem.findScalar(u32, closed, first_tail.variable) != null) first_tail = .closed;
        if (second_tail == .variable and std.mem.findScalar(u32, closed, second_tail.variable) != null) second_tail = .closed;
        try require(std.meta.eql(first_tail, second_tail));
        try self.consume(evidence.residual);
    }
    fn handle(self: *Effects, id: core.Id, depth: usize) Error!void {
        const n = self.m.node(id);
        const provider = self.m.node(try self.resolve(n.a));
        const shape = self.m.types.node(self.m.typeOf(n.a));
        try require(try equal(self.m, self.m.typeOf(n.a), provider.ty, 0, self.remaining));
        var operations: [2]T.Operation = undefined;
        var handler: Handler = .{ .parent = self.handlers };
        if (provider.tag == .effect_provider) {
            try require(shape.tag == .provider);
            operations[0] = try self.providerOperation(provider.a, shape.a, depth + 1);
            handler.operations = operations[0..1];
            const operation = self.m.types.node(self.m.typeOf(provider.a));
            const implementation_id = try self.resolve(provider.b);
            const implementation = self.m.node(implementation_id);
            const arrow = self.m.types.node(implementation.ty);
            try require(operation.tag == .function and arrow.tag == .function);
            try require(try equal(self.m, operation.a, arrow.a, 0, self.remaining) and try equal(self.m, operation.b, arrow.b, 0, self.remaining));
            try require(sameRow(self.m, shape.c, arrow.c, self.closed_rows));
            try self.consume(arrow.c);
            if (implementation.tag == .reference) {
                const reference = self.m.reference(implementation_id);
                const producer = try targetOwner(self.m, self.units, reference, self.workspace);
                const binding = producer.bindings[reference.binding];
                if (binding.kind == .global) {
                    var proof: Named = .{ .workspace = self.workspace, .m = self.m, .units = self.units, .remaining = self.remaining, .variables = self.variables, .row_owners = self.row_owners, .ambient = self.ambient };
                    try proof.functionValue(implementation_id, reference, depth + 1);
                }
            } else try require(implementation.tag == .closure);
            try self.visit(provider.b, depth + 1);
            try result(self.m, n.ty, self.m.typeOf(n.b), self.remaining);
        } else {
            try require(provider.tag == .state_provider and shape.tag == .state_provider);
            operations[0] = try self.providerOperation(provider.a, shape.a, depth + 1);
            operations[1] = try self.providerOperation(provider.b, shape.b, depth + 1);
            handler.operations = &operations;
            const read = self.m.types.node(self.m.typeOf(provider.a));
            const write = self.m.types.node(self.m.typeOf(provider.b));
            try require(read.tag == .function and read.a == T.unit and write.tag == .function and write.b == T.unit);
            try require(try equal(self.m, shape.c, read.b, 0, self.remaining) and try equal(self.m, shape.c, write.a, 0, self.remaining));
            try require(try equal(self.m, shape.c, self.m.typeOf(provider.c), 0, self.remaining));
            const output = self.m.types.node(n.ty);
            try require(output.tag == .product and output.b == 2);
            const fields = self.m.types.list(.{ .start = output.a, .len = output.b });
            try require(try equal(self.m, fields[0], shape.c, 0, self.remaining));
            try result(self.m, fields[1], self.m.typeOf(n.b), self.remaining);
            try self.visit(provider.c, depth + 1);
        }
        try self.handlerRows(id, &handler, shape);
        self.handlers = &handler;
        defer self.handlers = handler.parent;
        try self.visit(n.b, depth + 1);
    }
    fn requestLoop(self: *Effects, id: core.Id, depth: usize) Error!void {
        const n = self.m.node(id);
        const info = self.m.requestLoopInfo(id);
        try require(n.ty == T.unit);
        if (!self.checked_calls) try require(info.carries.len == 0 and info.state_type == T.unit and info.completion_state_bindings.len == 0);
        const computation_type = self.m.types.node(self.m.typeOf(info.computation));
        try require(computation_type.tag == .nominal and computation_type.a == std.math.maxInt(u32) and computation_type.b == 5);
        const computation_arguments = self.m.types.nominalArguments(computation_type);
        try require(computation_arguments.len == 1);
        const action = self.m.types.node(computation_arguments[0]);
        const selected = self.m.types.node(info.action_type);
        try require(action.tag == .function and action.a == T.unit and selected.tag == .function and selected.a == T.unit);
        try require(try equalWithRows(self.m, action.b, info.value_type, self.closed_rows, 0, self.remaining));
        try require(try equalWithRows(self.m, selected.b, info.value_type, self.closed_rows, 0, self.remaining));
        const computation = self.m.node(try self.resolve(info.computation));
        var actual_rows = self.closed_rows;
        if (computation.tag == .computation) {
            const callback = self.m.node(computation.a);
            if (callback.tag == .closure) actual_rows = self.m.closures[callback.a].closed_rows;
        }
        if (!sameOwnedRow(self.m, action.c, selected.c, actual_rows, self.closed_rows)) {
            // A request selects the surrounding ambient as well as its handled
            // operations. The actual computation may require a smaller row.
            // Each endpoint still needs its own producer's closing certificate.
            var views: @import("package_contracts.zig").Context = .{ .types = &self.m.types, .remaining = self.remaining };
            var owner: Named = .{ .workspace = self.workspace, .m = self.m, .units = self.units, .remaining = self.remaining };
            try owner.initializeViews(self.closed_rows, &views, depth + 1);
            var principal: @import("package_contracts.zig").Principal = .{ .left = &self.m.types, .right = &self.m.types, .remaining = self.remaining, .views = &views, .left_rows = actual_rows, .foreign_views = true };
            try principal.validate(computation_arguments[0], info.action_type);
        }
        try self.visit(info.computation, depth + 1);
        const arms = self.m.requestArms(id);
        var operations: [256]T.Operation = undefined;
        var selected_labels: [256]bool = @splat(false);
        const labels = self.m.types.rowLabels(selected.c);
        try require(labels.len <= selected_labels.len);
        try require(arms.len <= operations.len);
        for (arms, 0..) |arm, index| {
            const operation = self.m.types.operation(arm.operation);
            for (operations[0..index]) |earlier| try require(!try self.sameOperation(earlier, operation));
            operations[index] = operation;
            var present = false;
            for (labels, 0..) |label, slot| {
                if (selected_labels[slot] or !try self.sameOperation(operation, self.m.types.operation(label))) continue;
                selected_labels[slot] = true;
                present = true;
                break;
            }
            try require(present);
            const callback = self.m.node(arm.callback);
            try require(callback.tag == .closure);
            const arrow = try callable(self.m, callback.ty, self.remaining);
            const closure = self.m.closures[callback.a];
            try require(try equalWithRows(self.m, callback.ty, closure.function_type, closure.closed_rows, 0, self.remaining));
            try require(try equalWithRows(self.m, arrow.a, closure.parameter.ty, closure.closed_rows, 0, self.remaining));
            try result(self.m, arrow.b, self.m.typeOf(closure.body), self.remaining);
            const input = self.m.types.node(arrow.a);
            const output = self.m.types.node(arrow.b);
            try require(input.tag == .product and input.b == 2 and output.tag == .nominal and output.a == std.math.maxInt(u32) and output.b == 6);
            const input_parts = self.m.types.list(.{ .start = input.a, .len = input.b });
            const output_parts = self.m.types.nominalArguments(output);
            try require(output_parts.len == 3 and input_parts[1] == info.state_type and output_parts[1] == info.state_type);
            try require(try equal(self.m, output_parts[2], info.result_type, 0, self.remaining));
            try declaredOperation(self.m, self.units, operation, input_parts[0], output_parts[0], self.remaining);
            if (operation.instance.decl != 0) {
                const selector = self.m.node(try self.resolve(arm.selector));
                try require(selector.tag == .operation_value);
                const value = self.m.operation_values[selector.a];
                try require(try self.sameOperation(operation, .{ .identity = value.identity, .instance = value.instance, .arguments = value.arguments }));
                const signature = self.m.types.node(value.signature);
                try require(signature.tag == .function and try equal(self.m, input_parts[0], signature.a, 0, self.remaining) and try equal(self.m, output_parts[0], signature.b, 0, self.remaining));
                try self.visit(arm.selector, depth + 1);
            } else try require(arm.selector == 0);
            // Clauses execute outside the installation and may forward to an
            // older owner. Their own latent proof cannot borrow this handler.
            try self.execute(arm.callback, null, depth + 1);
        }
        var handler: Handler = .{ .operations = operations[0..arms.len], .parent = self.handlers };
        {
            self.handlers = &handler;
            defer self.handlers = handler.parent;
            try self.consume(selected.c);
            if (computation.tag == .computation) try self.execute(computation.a, null, depth + 1);
        }
        try self.visit(info.completion_body, depth + 1);
    }
    fn execute(self: *Effects, id: core.Id, argument: ?core.Id, depth: usize) Error!void {
        try self.visit(id, depth + 1);
        const node_ = self.m.node(id);
        const arrow = try callable(self.m, node_.ty, self.remaining);
        if (node_.tag != .closure) {
            try self.consume(arrow.c);
            return;
        }
        const callback = self.m.closures[node_.a];
        const caller_ambient = self.ambient;
        self.ambient = self.m.types.row(arrow.c);
        defer self.ambient = caller_ambient;
        try self.consumeLabels(self.m.types.row(arrow.c));
        const caller_rows = self.closed_rows;
        var rows: Named.RowOwner = .{ .closed = caller_rows, .generic = .{}, .parent = self.row_owners };
        self.row_owners = &rows;
        defer self.row_owners = rows.parent;
        self.closed_rows = callback.closed_rows;
        defer self.closed_rows = caller_rows;
        const caller_arguments = self.arguments_len;
        defer self.arguments_len = caller_arguments;
        if (argument) |actual| {
            try require(self.arguments_len < self.arguments_stack.len);
            self.arguments_stack[self.arguments_len] = .{ .binding = callback.parameter.binding, .node = actual };
            self.arguments_len += 1;
        }
        try self.visit(callback.body, depth + 1);
    }
    fn namedCall(self: *Effects, id: core.Id, depth: usize) Error!void {
        var checked = self.checked_calls;
        if (self.workspace) |workspace| checked = checked or workspace.proved(self.m);
        if (!checked) try taskNamedContextWorkspace(self.m, self.units, id, false, self.remaining, self.workspace);
        const call = try executableCall(self.m, self.units, id, self.remaining, self.workspace);
        var signature = call.callee_type;
        for (call.arguments) |_| {
            const arrow = self.m.types.node(signature);
            try require(arrow.tag == .function);
            try self.consume(arrow.c);
            signature = arrow.b;
        }
        const prior_checked = self.checked_calls;
        self.checked_calls = true;
        defer self.checked_calls = prior_checked;
        try self.arguments(call.arguments, depth);
    }
    fn visit(self: *Effects, id: core.Id, depth: usize) Error!void {
        if (id == 0) return;
        try require(depth < 128 and self.remaining.* != 0);
        self.remaining.* -= 1;
        const n = self.m.node(id);
        switch (n.tag) {
            .invalid, .contract_method, .associated, .result_associated => return error.InvalidArtifact,
            .request_loop => try self.requestLoop(id, depth + 1),
            .handle => try self.handle(id, depth + 1),
            .task => {
                try @import("task_core.zig").validateOperationContextWorkspace(self.m, self.units, id, self.remaining, self.workspace);
                const operation: @import("task_types.zig").Op = @fromBackingInt(n.c);
                const operands = self.m.children(id);
                for (operands) |operand| try self.visit(operand, depth + 1);
                if (operation == .scope or operation == .spawn or operation == .split) {
                    var position: usize = 0;
                    if (operation == .spawn) position = 1;
                    if (operation == .split) position = 2;
                    var callback_id = operands[position];
                    if (operation == .spawn) callback_id = try @import("task_core.zig").callable(self.m, callback_id);
                    const callback = self.m.closure(callback_id);
                    const arrow = try callable(self.m, self.m.typeOf(operands[position]), self.remaining);
                    try self.consume(arrow.c);
                    var nested: Effects = .{ .workspace = self.workspace, .m = self.m, .units = self.units, .target_module = self.m, .target = self.m.types.row(arrow.c), .closed_rows = callback.closed_rows, .remaining = self.remaining, .checked_calls = self.checked_calls, .variables = self.variables, .handlers = self.handlers };
                    try require(nested.target.labels.len <= nested.seen.len);
                    try nested.visit(callback.body, depth + 1);
                }
            },
            .effect_scope => {
                const callback_node = self.m.node(n.a);
                try require(callback_node.tag == .closure);
                const callback = self.m.closures[callback_node.a];
                const arrow = self.m.types.node(callback.function_type);
                try require(arrow.tag == .function and self.m.types.node(callback.parameter.ty).tag == .scoped);
                try require(try equalWithRows(self.m, arrow.a, callback.parameter.ty, callback.closed_rows, 0, self.remaining));
                try result(self.m, n.ty, arrow.b, self.remaining);
                try self.consume(arrow.c);
                // The enclosing lifetime reader proves the fresh owner and
                // its nonescape. Check its future callback's effects here;
                // constructing Code must not execute that callback now.
                var nested: Effects = .{ .workspace = self.workspace, .m = self.m, .units = self.units, .target_module = self.m, .target = self.m.types.row(arrow.c), .closed_rows = callback.closed_rows, .remaining = self.remaining, .checked_calls = self.checked_calls, .variables = self.variables, .handlers = self.handlers };
                try require(nested.target.labels.len <= nested.seen.len);
                try nested.visit(callback.body, depth + 1);
            },
            .package_pack => try self.visit(n.a, depth + 1),
            .package_unpack => {
                try self.visit(n.a, depth + 1);
                try self.visit(self.m.packageOpening(id).body, depth + 1);
            },
            .constant, .reference, .constructor_function, .primitive_function, .panic, .type_constructor, .effect_reflection => {},
            .closure, .suspend_ => {
                const closure = self.m.closures[n.a];
                var shape = self.m.types.node(n.ty);
                var qualifiers: usize = 0;
                while (shape.tag == .usage) {
                    try require(qualifiers < 128 and self.remaining.* != 0);
                    self.remaining.* -= 1;
                    qualifiers += 1;
                    shape = self.m.types.node(shape.a);
                }
                if (n.tag == .closure) try require(shape.tag == .function) else try require(shape.tag == .demand);
                var rows: Named.RowOwner = .{ .closed = self.closed_rows, .generic = .{}, .parent = self.row_owners };
                var nested: Effects = .{ .workspace = self.workspace, .ambient = self.m.types.row(shape.c), .row_owners = &rows, .m = self.m, .units = self.units, .target_module = self.m, .target = self.m.types.row(shape.c), .closed_rows = closure.closed_rows, .remaining = self.remaining, .checked_calls = self.checked_calls, .variables = self.variables };
                try require(nested.target.labels.len <= nested.seen.len);
                // Defining a callable or demand does not execute its effects.
                // Its own latent row still has to describe the actual body,
                // independently of handlers surrounding its construction.
                try nested.visit(closure.body, depth + 1);
            },
            .operation_value => {
                const operation = self.m.operation_values[n.a];
                try self.visit(operation.capability, depth + 1);
                try self.visit(operation.witness, depth + 1);
            },
            .resource_acquire, .resource_scope => {
                try self.consumeOperation(.{ .identity = .{ .unit = 0, .decl = 1 }, .instance = .{ .unit = 0, .decl = 0 }, .arguments = .{} });
                try self.execute(n.a, null, depth + 1);
                try self.execute(n.b, null, depth + 1);
                if (n.tag == .resource_scope) try self.execute(n.c, null, depth + 1);
            },
            .resource_release => {
                try self.consumeOperation(.{ .identity = .{ .unit = 0, .decl = 1 }, .instance = .{ .unit = 0, .decl = 0 }, .arguments = .{} });
                try self.visit(n.a, depth + 1);
            },
            .usage_read, .usage_share => try self.visit(n.a, depth + 1),
            .usage_borrow => {
                try self.visit(n.a, depth + 1);
                try self.execute(n.b, n.a, depth + 1);
            },
            .staging => {
                const op: staging.Op = @fromBackingInt(n.c);
                // Construction and earlier-stage lift operands are pure. Their
                // separate stage/shape checks retain that boundary's authority.
                if (op == .quote or op == .lift) return;
                if (op == .splice or op == .emit) {
                    const shape = staging.codeInfo(&self.m.types, self.m.typeOf(n.a)) orelse return error.InvalidArtifact;
                    try self.consume(shape.effects);
                }
                if (op != .splice) try self.visit(n.a, depth + 1);
                try self.visit(n.b, depth + 1);
            },
            .apply => {
                const callee_id = try self.resolve(n.a);
                const callee = self.m.node(callee_id);
                if (callee.tag == .operation_value) {
                    const operation = self.m.operation_values[callee.a];
                    try self.consumeOperation(.{ .identity = operation.identity, .instance = operation.instance, .arguments = operation.arguments });
                    const signature = self.m.types.node(operation.signature);
                    try require(signature.tag == .function);
                    // A checked contextual operation view may conservatively
                    // retain unused enclosing annotation labels. Its actual
                    // operation is still independently required above.
                    try self.consumeLabels(self.m.types.row(signature.c));
                } else if (callee.tag == .closure) {
                    const closure = self.m.closures[callee.a];
                    const arrow = try callable(self.m, closure.function_type, self.remaining);
                    const caller_ambient = self.ambient;
                    self.ambient = self.m.types.row(arrow.c);
                    defer self.ambient = caller_ambient;
                    try self.consumeLabels(self.m.types.row(arrow.c));
                    try require(self.arguments_len < self.arguments_stack.len);
                    self.arguments_stack[self.arguments_len] = .{ .binding = closure.parameter.binding, .node = n.b };
                    self.arguments_len += 1;
                    defer self.arguments_len -= 1;
                    const caller_rows = self.closed_rows;
                    self.closed_rows = closure.closed_rows;
                    defer self.closed_rows = caller_rows;
                    try self.visit(closure.body, depth + 1);
                } else if (callee.tag == .reference) {
                    const arrow = try callable(self.m, callee.ty, self.remaining);
                    try self.consume(arrow.c);
                } else try require(callee.tag == .constructor_function or (callee.tag == .primitive_function and self.m.primitives[callee.a].kind == .scalar));
                try self.visit(n.a, depth + 1);
                try self.visit(n.b, depth + 1);
            },
            .resolver_op => {
                try resolverShape(self.m, id);
                const metadata = self.m.resolverInfo(id);
                try self.visit(metadata.resolver, depth + 1);
                const arguments_ = self.m.resolverArguments(id);
                switch (metadata.operation) {
                    .monad => {},
                    .forward => try self.arguments(arguments_, depth),
                    .run => try self.execute(arguments_[0], null, depth + 1),
                    .pure, .bind, .iterate => try self.namedCall(id, depth),
                }
            },
            .call => try self.namedCall(id, depth),
            .force => {
                const shape = self.m.types.node(self.m.typeOf(n.a));
                try require(shape.tag == .demand);
                const producer = self.m.node(try self.resolve(n.a));
                if (producer.tag == .suspend_) {
                    try self.consumeLabels(self.m.types.row(shape.c));
                    const closure = self.m.closures[producer.a];
                    const caller_rows = self.closed_rows;
                    self.closed_rows = closure.closed_rows;
                    defer self.closed_rows = caller_rows;
                    try self.visit(closure.body, depth + 1);
                } else try self.consume(shape.c);
                try self.visit(n.a, depth + 1);
            },
            .scalar, .logical, .record_merge, .type_same, .effect_provider, .proof_guard => {
                try self.visit(n.a, depth + 1);
                try self.visit(n.b, depth + 1);
            },
            .if_value, .if_stmt, .state_provider => {
                try self.visit(n.a, depth + 1);
                try self.visit(n.b, depth + 1);
                try self.visit(n.c, depth + 1);
            },
            .array_op => {
                try self.arguments(self.m.children(id), depth);
                if (self.m.arrayOperation(id) == .generate) try self.execute(self.m.children(id)[1], null, depth + 1);
            },
            .block, .suite, .product, .record, .array, .break_ => try self.arguments(self.m.children(id), depth),
            .bind, .construct => try self.visit(n.b, depth + 1),
            .return_, .project, .computation => try self.visit(n.a, depth + 1),
            .pattern_bind, .request_decision => {
                try self.visit(n.b, depth + 1);
                try self.visit(n.c, depth + 1);
            },
            .loop => {
                const loop = self.m.loops[n.a];
                try self.visit(loop.first, depth + 1);
                try self.visit(loop.end, depth + 1);
                try self.visit(loop.body, depth + 1);
            },
            .match => {
                try self.arguments(self.m.matchInputs(id), depth);
                for (self.m.matchArms(id)) |arm| {
                    try self.visit(arm.guard, depth + 1);
                    try self.visit(arm.body, depth + 1);
                }
            },
            .update => {
                const update = self.m.updates[n.a];
                try self.visit(update.root, depth + 1);
                try self.visit(update.value, depth + 1);
                for (self.m.updateSelectors(id)) |step| if (step.kind == .index) try self.visit(step.index, depth + 1);
            },
        }
    }
};
// A call's selected row includes evaluating its argument, in addition to the
// callee's latent effects. Prove both reads before accepting that row: a pure
// generic identity applied to Read () still has the effect of its argument.
fn selectedEffects(m: *const core.Module, units: []const *const core.Module, id: core.Id, producer: *const core.Module, body: *const core.Body, closed_rows: T.List, variables: []const T.Id, formal_variables: []const T.Id, substitutions: []const T.Id, instance: ?*const @import("package_contracts.zig").Principal, row_owners: ?*const Named.RowOwner, ambient: ?T.Effects.Row, remaining: *usize, workspace: ?*@import("scheme_equations.zig").Workspace, depth: usize) Error!void {
    const call = try executableCall(m, units, id, remaining, workspace);
    var signature = call.callee_type;
    var formal = producer.bindings[body.binding].ty;
    var bindings: [32]T.Id = @splat(0);
    @memcpy(bindings[0..formal_variables.len], substitutions[0..formal_variables.len]);
    for (call.arguments) |argument| {
        const arrow = m.types.node(signature);
        const declared = producer.types.node(formal);
        try require(arrow.tag == .function);
        var effects: Effects = .{ .workspace = workspace, .checked_calls = true, .m = m, .units = units, .target_module = m, .target = m.types.row(arrow.c), .closed_rows = closed_rows, .remaining = remaining, .variables = variables, .row_owners = row_owners, .ambient = ambient };
        try require(effects.target.labels.len <= effects.seen.len);
        try effects.visit(argument, depth + 1);
        var used: [256]bool = @splat(false);
        for (producer.types.rowLabels(declared.c)) |label| {
            const operation = producer.types.operations[label];
            var found = false;
            for (m.types.rowLabels(arrow.c), 0..) |selected, index| {
                if (used[index]) continue;
                const candidate = m.types.operations[selected];
                if (!cross.sameIdentity(producer, operation.identity, m, candidate.identity) or !cross.sameIdentity(producer, operation.instance, m, candidate.instance)) continue;
                const xs = producer.types.list(operation.arguments);
                const ys = m.types.list(candidate.arguments);
                if (xs.len != ys.len) continue;
                var mapping = bindings;
                var matched = true;
                for (xs, ys) |x, y| cross.match(producer, x, m, y, formal_variables, &mapping, remaining, depth + 1) catch {
                    matched = false;
                };
                if (!matched) continue;
                bindings = mapping;
                effects.seen[index] = true;
                used[index] = true;
                found = true;
                break;
            }
            try require(found);
        }
        const tail = producer.types.row(declared.c).tail;
        if (tail == .variable) {
            if (std.mem.findScalar(u32, producer.types.list(body.scheme.row_variables), tail.variable)) |ordinal| {
                const principal = instance orelse return error.InvalidArtifact;
                const witness = principal.scheme_row_witnesses[ordinal] orelse return error.InvalidArtifact;
                for (m.types.rowLabels(witness.row), 0..) |label, index| {
                    if (witness.excluded.isSet(index)) continue;
                    try effects.consumeTarget(m.types.operations[label], &used);
                }
            }
        }
        // Source selection may retain an unused prefix of the actual enclosing
        // ambient. That lexical producer row is independent of this call's
        // selected arrow; it grants no purity or executable body authority.
        if (ambient) |owner| {
            const labels = m.types.effects.labels[owner.labels.start..][0..owner.labels.len];
            var allowed: [256]bool = @splat(false);
            try require(labels.len <= allowed.len);
            for (effects.seen[0..effects.target.labels.len], m.types.rowLabels(arrow.c)) |*seen, label| {
                if (seen.*) continue;
                for (labels, 0..) |actual, index| {
                    if (allowed[index] or !try effects.sameOperation(m.types.operations[label], m.types.operations[actual])) continue;
                    allowed[index] = true;
                    seen.* = true;
                    break;
                }
            }
        }
        for (effects.seen[0..effects.target.labels.len]) |seen| try require(seen);
        signature = arrow.b;
        formal = declared.b;
    }
}
pub fn quoteEffects(m: *const core.Module, quote: core.Node, closed_rows: T.List, remaining: *usize) Error!void {
    return quoteEffectsContext(m, &.{}, quote, closed_rows, remaining);
}
pub fn quoteEffectsContext(m: *const core.Module, units: []const *const core.Module, quote: core.Node, closed_rows: T.List, remaining: *usize) Error!void {
    return quoteEffectsContextWorkspace(m, units, quote, closed_rows, remaining, null);
}
pub fn quoteEffectsContextWorkspace(m: *const core.Module, units: []const *const core.Module, quote: core.Node, closed_rows: T.List, remaining: *usize, workspace: ?*@import("scheme_equations.zig").Workspace) Error!void {
    const shape = staging.codeInfo(&m.types, quote.ty) orelse return error.InvalidArtifact;
    try require(m.typeOf(quote.a) == T.never or try equalWithRows(m, shape.result, m.typeOf(quote.a), closed_rows, 0, remaining));
    const row = shape.effects;
    const target = m.types.effects.node(row);
    try require(target.labels.len <= 256 and target.tail != .parameter);
    var effects: Effects = .{ .workspace = workspace, .m = m, .units = units, .target_module = m, .target = target, .closed_rows = closed_rows, .remaining = remaining };
    try effects.visit(quote.a, 0);
    for (effects.seen[0..target.labels.len]) |seen| try require(seen);
    // An inferred open tail is a conservative upper bound. It never licenses
    // pure execution: run separately requires a genuinely closed empty row.
}
fn descriptorFields(m: *const core.Module, target: T.Id, output: T.Node, remaining: *usize) Error!void {
    try require(output.tag == .record);
    const original = m.types.node(target);
    if (original.tag == .record) {
        try require(original.b == output.b);
        for (0..original.b) |i| {
            const field = m.types.recordField(original, i);
            const published = m.types.recordField(output, i);
            const described = staging.descriptorInfo(&m.types, published.ty) orelse return error.InvalidArtifact;
            try require(field.name == published.name and try equal(m, field.ty, described, 0, remaining));
        }
        return;
    }
    try require(original.tag == .nominal);
    var proof: Named = .{ .m = m, .remaining = remaining };
    const family_index = try nominalOwner(m, original, remaining);
    try require(!m.nominals[family_index].private and !m.nominals[family_index].is_opaque);
    const constructors = m.nominalConstructors(family_index);
    const first = m.types.node(m.constructors[constructors[0]].payload);
    if (first.tag != .record) return require(output.b == 0);
    var count: usize = 0;
    for (0..first.b) |index| {
        const field = m.types.recordField(first, index);
        var common = true;
        for (constructors) |constructor_index| {
            try proof.step(0);
            const payload = m.types.node(m.constructors[constructor_index].payload);
            var found = false;
            if (payload.tag == .record) for (0..payload.b) |i| {
                try proof.step(0);
                if (m.types.recordField(payload, i).name == field.name) found = true;
            };
            if (!found) common = false;
        }
        if (!common) continue;
        try require(count < output.b);
        const published = m.types.recordField(output, count);
        const described = staging.descriptorInfo(&m.types, published.ty) orelse return error.InvalidArtifact;
        try require(published.name == field.name);
        for (constructors) |constructor_index| {
            try proof.step(0);
            const constructor = m.constructors[constructor_index];
            const variables = try proof.constructorVariables(family_index, constructor);
            var bindings: [32]T.Id = @splat(0);
            const arrow = m.types.node(constructor.scheme.root);
            try require(arrow.tag == .function);
            try proof.match(arrow.b, target, variables, &bindings, 0);
            for (bindings[0..variables.len]) |binding| try require(binding != 0);
            const payload = m.types.node(constructor.payload);
            for (0..payload.b) |i| {
                try proof.step(0);
                const actual = m.types.recordField(payload, i);
                if (actual.name == field.name) try proof.match(actual.ty, described, variables, &bindings, 0);
            }
        }
        count += 1;
    }
    try require(count == output.b);
}
pub fn shapes(m: *const core.Module) Error!void {
    var remaining: usize = 1_000_000;
    for (m.types.nodes, 0..) |n, id| {
        if (n.tag != .nominal or !staging.isIdentity(n.a, n.b)) continue;
        if (n.b == staging.code_identity.decl) {
            const shape = staging.codeInfo(&m.types, @intCast(id)) orelse return error.InvalidArtifact;
            try require(shape.result != 0);
            const arguments = m.types.nominalArguments(n);
            try require(m.types.node(arguments[1]).b == 0);
        } else {
            const target = staging.descriptorInfo(&m.types, @intCast(id)) orelse return error.InvalidArtifact;
            try require(target != 0);
        }
    }
    for (m.nodes) |n| {
        if (n.tag != .staging) continue;
        const op: staging.Op = @fromBackingInt(n.c);
        const input = m.typeOf(n.a);
        switch (op) {
            .quote => try require(staging.codeInfo(&m.types, n.ty) != null),
            .lift => {
                try result(m, n.ty, input, &remaining);
                var ownership: @import("usage_check.zig").Work = .{ .remaining = remaining };
                const contains_usage = @import("usage_check.zig").containsNominalWork(&m.types, m.nominals, input, &ownership) catch return error.InvalidArtifact;
                remaining = ownership.remaining;
                try require(!contains_usage and (staging.liftable(&m.types, input) catch false));
            },
            .splice, .emit, .run => {
                const shape = staging.codeInfo(&m.types, input) orelse return error.InvalidArtifact;
                try result(m, n.ty, shape.result, &remaining);
                if (op == .run) {
                    const row = m.types.effects.node(shape.effects);
                    try require(row.labels.len == 0 and row.tail == .closed);
                }
            },
            .same => {
                try require(n.ty == T.boolean and staging.descriptorInfo(&m.types, input) != null and staging.descriptorInfo(&m.types, m.typeOf(n.b)) != null);
            },
            .fields => {
                const target = staging.descriptorInfo(&m.types, input) orelse return error.InvalidArtifact;
                try descriptorFields(m, target, m.types.node(n.ty), &remaining);
            },
            .describe => {
                const shape = staging.codeInfo(&m.types, input) orelse return error.InvalidArtifact;
                const output = m.types.node(n.ty);
                try require(output.tag == .record and output.b == 2);
                var found_result = false;
                var found_effects = false;
                for (0..2) |i| {
                    const field = m.types.recordField(output, i);
                    const name = m.fieldSpelling(field.name) orelse return error.InvalidArtifact;
                    if (std.mem.eql(u8, name, "result")) {
                        try require(!found_result);
                        found_result = true;
                        const target = staging.descriptorInfo(&m.types, field.ty) orelse return error.InvalidArtifact;
                        try require(try equal(m, shape.result, target, 0, &remaining));
                    } else {
                        try require(std.mem.eql(u8, name, "effects") and !found_effects);
                        found_effects = true;
                        const effect = m.types.node(field.ty);
                        try require(effect.tag == .nominal and effect.a == T.effect_set_identity.unit and effect.b == T.effect_set_identity.decl and m.types.nominalArguments(effect).len == 0);
                    }
                }
                try require(found_result and found_effects);
            },
        }
    }
}

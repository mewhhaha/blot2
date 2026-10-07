//! Validate normalized principal payloads before exposing any imported scheme.
const std = @import("std");
const PI = @import("principal_interface.zig");
const T = @import("types.zig");
pub const Error = error{InvalidArtifact};

fn require(condition: bool) Error!void {
    if (!condition) return error.InvalidArtifact;
}
fn range(start: u32, count: u32, length: usize) Error!void {
    try require(start <= length and count <= length - start);
}
fn list(owner: *const PI.Interface, value: T.List) Error![]const u32 {
    try range(value.start, value.len, owner.graph.extra.len);
    return owner.graph.extra[value.start..][0..value.len];
}
fn ty(owner: *const PI.Interface, id: T.Id) Error!void {
    try require(id < owner.graph.nodes.len);
}
fn names(values: []const u32, count: usize) Error!void {
    for (values) |id| try require(id < count);
}
fn units(id: u32, count: usize) Error!void {
    try require(id == 0 or id == std.math.maxInt(u32) or id <= count);
}
fn scheme(owner: *const PI.Interface, value: T.Scheme) Error!void {
    try ty(owner, value.root);
    for (try list(owner, value.variables)) |id| {
        try ty(owner, id);
        try require(owner.graph.nodes[id].tag == .variable);
    }
    for (try list(owner, value.row_variables)) |id| try require(id < owner.graph.row_variable_count);
    for (try list(owner, value.closed_rows)) |id| try require(id < owner.graph.row_variable_count);
    try range(value.obligations.start, value.obligations.len, owner.obligations.len);
}

pub fn validate(owner: *const PI.Interface, symbol_count: usize, unit_count: usize) Error!void {
    try require(owner.unit != 0 and owner.unit <= unit_count);
    try require(owner.graph.nodes.len >= 6 and owner.graph.rows.len != 0 and owner.graph.operations.len >= 2);
    for ([_]T.Tag{ .absent, .unit, .boolean, .u32, .f32, .never }, owner.graph.nodes[0..6]) |tag, node| try require(node.tag == tag and node.a == 0 and node.b == 0 and node.c == 0);
    for (owner.graph.nodes) |node| switch (node.tag) {
        .absent, .unit, .boolean, .u32, .f32, .never => {},
        .variable => try require(node.b == 0 and node.c == 0),
        .function => {
            try ty(owner, node.a);
            try ty(owner, node.b);
            try require(node.c < owner.graph.rows.len);
        },
        .product => for (try list(owner, .{ .start = node.a, .len = node.b })) |child| try ty(owner, child),
        .record => {
            const count = std.math.mul(u32, node.b, 2) catch return error.InvalidArtifact;
            const fields = try list(owner, .{ .start = node.a, .len = count });
            for (0..node.b) |index| {
                try require(fields[index * 2] != 0 and fields[index * 2] < symbol_count);
                try ty(owner, fields[index * 2 + 1]);
                // Record payloads retain source declaration order. Layouts
                // canonicalize separately; validateGraph checks uniqueness.
            }
        },
        .nominal => {
            try units(node.a, unit_count);
            try require(node.c < owner.graph.extra.len);
            const start = std.math.add(u32, node.c, 1) catch return error.InvalidArtifact;
            for (try list(owner, .{ .start = start, .len = owner.graph.extra[node.c] })) |child| try ty(owner, child);
        },
        .type_constructor => try units(node.a, unit_count),
        .array, .list, .resolver => try ty(owner, node.a),
        .demand, .provider => {
            try ty(owner, node.a);
            try require(node.c < owner.graph.rows.len);
        },
        .state_provider => {
            try ty(owner, node.a);
            try ty(owner, node.b);
            try ty(owner, node.c);
        },
    };
    for (owner.graph.rows) |row| {
        try require(row.cursor == 0);
        try range(row.labels.start, row.labels.len, owner.graph.labels.len);
        for (owner.graph.labels[row.labels.start..][0..row.labels.len]) |label| try require(label != 0 and label < owner.graph.operations.len);
        if (row.tail == .variable) try require(row.tail.variable < owner.graph.row_variable_count);
    }
    try require(owner.graph.rows[0].labels.len == 0 and owner.graph.rows[0].tail == .closed);
    for (owner.graph.operations) |operation| {
        try units(operation.identity.unit, unit_count);
        for (try list(owner, operation.arguments)) |argument| try ty(owner, argument);
    }
    try require(owner.graph.operations[0].identity.unit == 0 and owner.graph.operations[0].identity.decl == 0);
    try require(owner.graph.operations[1].identity.unit == 0 and owner.graph.operations[1].identity.decl == 1);
    for (owner.patterns.nodes) |node| switch (node.kind) {
        .binding => try ty(owner, node.a),
        .tuple, .array => {
            try range(node.a, node.b, owner.patterns.extra.len);
            for (owner.patterns.extra[node.a..][0..node.b]) |id| try require(id < owner.patterns.nodes.len);
        },
        .record => {
            const count = std.math.mul(u32, node.b, 2) catch return error.InvalidArtifact;
            try range(node.a, count, owner.patterns.extra.len);
            for (0..node.b) |index| {
                try require(owner.patterns.extra[node.a + index * 2] < symbol_count);
                try require(owner.patterns.extra[node.a + index * 2 + 1] < owner.patterns.nodes.len);
            }
        },
    };
    for (owner.bindings) |binding| {
        try require(binding.name < symbol_count);
        try ty(owner, binding.ty);
        try scheme(owner, binding.scheme);
        if (binding.external) |target| {
            try units(target.unit, unit_count);
            try require(target.binding != 0);
        }
    }
    try require(owner.obligations.len == owner.obligation_spans.len);
    for (owner.obligations) |obligation| {
        try ty(owner, obligation.ty);
        try ty(owner, obligation.result);
        try ty(owner, obligation.other);
        try ty(owner, obligation.signature);
        try require(obligation.source == 0 and obligation.name < symbol_count);
        try units(obligation.identity.unit, unit_count);
        try units(obligation.qualification_unit, unit_count);
    }
    for (owner.nominals) |nominal| {
        try ty(owner, nominal.alias);
        for (try list(owner, nominal.alias_rows)) |row| try require(row < owner.graph.row_variable_count);
        if (nominal.alias != 0) try require(nominal.constructors.len == 0);
        try units(nominal.identity.unit, unit_count);
        try require(nominal.name < symbol_count);
        for (try list(owner, nominal.parameters)) |id| try ty(owner, id);
        for (try list(owner, nominal.variables)) |id| try ty(owner, id);
        try range(nominal.patterns.start, nominal.patterns.len, owner.patterns.extra.len);
        for (owner.patterns.extra[nominal.patterns.start..][0..nominal.patterns.len]) |id| try require(id < owner.patterns.nodes.len);
        try names(try list(owner, nominal.parameter_names), symbol_count);
        for (try list(owner, nominal.constructors)) |id| try require(id < owner.constructors.len);
    }
    for (owner.contracts) |contract| {
        try units(contract.identity.unit, unit_count);
        try require(contract.name < symbol_count);
        for (try list(owner, contract.parameters)) |id| try ty(owner, id);
        for (try list(owner, contract.variables)) |id| {
            try ty(owner, id);
            try require(owner.graph.nodes[id].tag == .variable);
        }
        for (try list(owner, contract.row_variables)) |row| try require(row < owner.graph.row_variable_count);
        try names(try list(owner, contract.parameter_names), symbol_count);
        try require(contract.parameter_names.len == contract.variables.len and contract.patterns.len == contract.parameters.len);
        try range(contract.patterns.start, contract.patterns.len, owner.patterns.extra.len);
        for (owner.patterns.extra[contract.patterns.start..][0..contract.patterns.len]) |id| try require(id < owner.patterns.nodes.len);
        try range(contract.predicates.start, contract.predicates.len, owner.contract_predicates.len);
    }
    for (owner.contract_predicates) |predicate| {
        inline for (.{ "ty", "other", "result", "signature" }) |field| try ty(owner, @field(predicate, field));
        try require(predicate.source == 0 and predicate.name < symbol_count and predicate.explicit);
        try units(predicate.identity.unit, unit_count);
        try units(predicate.qualification_unit, unit_count);
    }
    for (owner.constructors) |constructor| {
        try units(constructor.identity.unit, unit_count);
        try require(constructor.name < symbol_count and constructor.nominal < owner.nominals.len);
        try scheme(owner, constructor.scheme);
        try ty(owner, constructor.payload);
    }
    for (owner.effect_families) |family| {
        try units(family.identity.unit, unit_count);
        try require(family.name < symbol_count);
        for (try list(owner, family.parameters)) |id| try ty(owner, id);
        for (try list(owner, family.variables)) |id| try ty(owner, id);
        try range(family.patterns.start, family.patterns.len, owner.patterns.extra.len);
        for (owner.patterns.extra[family.patterns.start..][0..family.patterns.len]) |id| try require(id < owner.patterns.nodes.len);
        try names(try list(owner, family.parameter_names), symbol_count);
        for (try list(owner, family.operations)) |id| try require(id < owner.effect_templates.len);
    }
    for (owner.effect_templates) |operation| {
        try units(operation.identity.unit, unit_count);
        try require(operation.name < symbol_count and operation.family < owner.effect_families.len);
        try ty(owner, operation.parameter);
        try ty(owner, operation.result);
    }
    for (owner.associated) |method| {
        try units(method.identity.unit, unit_count);
        try require(method.member < symbol_count and method.binding < owner.bindings.len);
    }
}

/// Structural type, operation and pattern edges must be acyclic. Nominal
/// declaration identities are leaves; recursive source data is represented by
/// those identities rather than a pointer back into this graph. Bounds must be
/// checked first, so this traversal never speculates about malformed indices.
pub fn validateGraph(allocator: std.mem.Allocator, owner: *const PI.Interface) (Error || std.mem.Allocator.Error)!void {
    // Reuse one symbol-stamp lane across every source record. Arbitrary
    // declaration order is legal; duplicate fields reject in linear work.
    var symbol_limit: usize = 0;
    for (owner.graph.nodes) |n| if (n.tag == .record) {
        for (0..n.b) |index| symbol_limit = @max(symbol_limit, @as(usize, owner.graph.extra[n.a + index * 2]) + 1);
    };
    const stamps = try allocator.alloc(u32, symbol_limit);
    defer allocator.free(stamps);
    @memset(stamps, 0);
    var generation: u32 = 0;
    for (owner.graph.nodes) |n| if (n.tag == .record) {
        generation = std.math.add(u32, generation, 1) catch return error.InvalidArtifact;
        for (0..n.b) |index| {
            const name = owner.graph.extra[n.a + index * 2];
            if (stamps[name] == generation) return error.InvalidArtifact;
            stamps[name] = generation;
        }
    };
    const graph = GraphEdges{ .owner = owner };
    const total = graph.total();
    const colors = try allocator.alloc(u2, total);
    defer allocator.free(colors);
    @memset(colors, 0);
    const Frame = struct { key: usize, next: usize = 0 };
    const frames = try allocator.alloc(Frame, total);
    defer allocator.free(frames);
    for (0..total) |root| {
        if (colors[root] != 0) continue;
        var depth: usize = 1;
        frames[0] = .{ .key = root };
        colors[root] = 1;
        while (depth != 0) {
            const current = &frames[depth - 1];
            const child = graph.child(current.key, current.next) orelse {
                colors[current.key] = 2;
                depth -= 1;
                continue;
            };
            current.next += 1;
            if (colors[child] == 1) return error.InvalidArtifact;
            if (colors[child] == 2) continue;
            colors[child] = 1;
            frames[depth] = .{ .key = child };
            depth += 1;
        }
    }
}

const GraphEdges = struct {
    owner: *const PI.Interface,
    fn rowStart(self: GraphEdges) usize {
        return self.owner.graph.nodes.len;
    }
    fn operationStart(self: GraphEdges) usize {
        return self.rowStart() + self.owner.graph.rows.len;
    }
    fn patternStart(self: GraphEdges) usize {
        return self.operationStart() + self.owner.graph.operations.len;
    }
    fn total(self: GraphEdges) usize {
        return self.patternStart() + self.owner.patterns.nodes.len;
    }
    fn child(self: GraphEdges, key: usize, index: usize) ?usize {
        const g = self.owner.graph;
        if (key < self.rowStart()) {
            const n = g.nodes[key];
            return switch (n.tag) {
                .function => switch (index) {
                    0 => n.a,
                    1 => n.b,
                    2 => self.rowStart() + n.c,
                    else => null,
                },
                .product => if (index < n.b) g.extra[n.a + index] else null,
                .record => if (index < n.b) g.extra[n.a + index * 2 + 1] else null,
                .nominal => if (index < g.extra[n.c]) g.extra[n.c + 1 + index] else null,
                .array, .list, .resolver => if (index == 0) n.a else null,
                .demand, .provider => switch (index) {
                    0 => n.a,
                    1 => self.rowStart() + n.c,
                    else => null,
                },
                .state_provider => switch (index) {
                    0 => n.a,
                    1 => n.b,
                    2 => n.c,
                    else => null,
                },
                else => null,
            };
        }
        if (key < self.operationStart()) {
            const row = g.rows[key - self.rowStart()];
            return if (index < row.labels.len) self.operationStart() + g.labels[row.labels.start + index] else null;
        }
        if (key < self.patternStart()) {
            const operation = g.operations[key - self.operationStart()];
            return if (index < operation.arguments.len) g.extra[operation.arguments.start + index] else null;
        }
        const p = self.owner.patterns;
        const n = p.nodes[key - self.patternStart()];
        return switch (n.kind) {
            .binding => if (index == 0) n.a else null,
            .tuple, .array => if (index < n.b) self.patternStart() + p.extra[n.a + index] else null,
            .record => if (index < n.b) self.patternStart() + p.extra[n.a + index * 2 + 1] else null,
        };
    }
};

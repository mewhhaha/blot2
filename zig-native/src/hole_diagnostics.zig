//! Bounded, independently owned semantic snapshots for editor holes. IDs name
//! this diagnostic's flat graph, never inference tables or future revisions.
const std = @import("std");
const T = @import("types.zig");
const ast = @import("ast.zig");
const Allocator = std.mem.Allocator;
pub const Kind = enum { truncated, absent, unit, boolean, u32, f32, never, variable, function, product, record, nominal, array, list, cursor, demand, type_constructor, resolver, provider, state_provider, effects, operation, row_variable, row_parameter };
pub const Span = struct { start: u32 = 0, len: u32 = 0 };
pub const Node = struct {
    kind: Kind,
    name: ?[]const u8 = null,
    identity: ?T.NominalIdentity = null,
    variable: ?u32 = null,
    children: Span = .{},
    effects: ?u32 = null,
};
pub const Edge = struct { name: ?[]const u8 = null, type: u32 };
pub const Binding = struct { name: []const u8, type: u32, requirements: Span = .{} };
pub const Requirement = struct {
    kind: T.ObligationKind,
    name: ?[]const u8 = null,
    subject: u32,
    argument: ?u32 = null,
    result: ?u32 = null,
    signature: ?u32 = null,
    explicit: bool,
};
pub const Snapshot = struct {
    expected: u32 = 0,
    nodes: []Node = &.{},
    edges: []Edge = &.{},
    scope: []Binding = &.{},
    requirements: []Requirement = &.{},
    enclosing: Span = .{},
    truncated: bool = false,

    pub fn deinit(self: Snapshot, allocator: Allocator) void {
        for (self.nodes) |node| if (node.name) |name| allocator.free(name);
        for (self.edges) |edge| if (edge.name) |name| allocator.free(name);
        for (self.scope) |binding| allocator.free(binding.name);
        for (self.requirements) |requirement| if (requirement.name) |name| allocator.free(name);
        allocator.free(self.nodes);
        allocator.free(self.edges);
        allocator.free(self.scope);
        allocator.free(self.requirements);
    }
    pub fn clone(self: Snapshot, allocator: Allocator) !Snapshot {
        var result: Snapshot = .{ .expected = self.expected, .enclosing = self.enclosing, .truncated = self.truncated };
        errdefer result.deinit(allocator);
        result.nodes = try allocator.dupe(Node, self.nodes);
        for (result.nodes) |*node| node.name = null;
        for (self.nodes, result.nodes) |old, *new| if (old.name) |name| {
            new.name = try allocator.dupe(u8, name);
        };
        result.edges = try allocator.dupe(Edge, self.edges);
        for (result.edges) |*edge| edge.name = null;
        for (self.edges, result.edges) |old, *new| if (old.name) |name| {
            new.name = try allocator.dupe(u8, name);
        };
        result.scope = try allocator.dupe(Binding, self.scope);
        for (result.scope) |*binding| binding.name = &.{};
        for (self.scope, result.scope) |old, *new| new.name = try allocator.dupe(u8, old.name);
        result.requirements = try allocator.dupe(Requirement, self.requirements);
        for (result.requirements) |*requirement| requirement.name = null;
        for (self.requirements, result.requirements) |old, *new| if (old.name) |name| {
            new.name = try allocator.dupe(u8, name);
        };
        return result;
    }
};

const Builder = struct {
    allocator: Allocator,
    nodes: std.ArrayList(Node) = .empty,
    edges: std.ArrayList(Edge) = .empty,
    scope: std.ArrayList(Binding) = .empty,
    requirements: std.ArrayList(Requirement) = .empty,
    memo: std.AutoHashMapUnmanaged(T.Id, u32) = .empty,
    remaining: usize = 1024,
    name_bytes: usize = 0,
    truncated: bool = false,

    fn deinit(self: *Builder) void {
        for (self.nodes.items) |node| if (node.name) |name| self.allocator.free(name);
        for (self.edges.items) |edge| if (edge.name) |name| self.allocator.free(name);
        for (self.scope.items) |binding| self.allocator.free(binding.name);
        for (self.requirements.items) |requirement| if (requirement.name) |name| self.allocator.free(name);
        self.nodes.deinit(self.allocator);
        self.edges.deinit(self.allocator);
        self.scope.deinit(self.allocator);
        self.requirements.deinit(self.allocator);
        self.memo.deinit(self.allocator);
    }
    fn saveName(self: *Builder, text: []const u8) ![]const u8 {
        const count = @min(text.len, 16384 - self.name_bytes);
        var length = count;
        while (length != 0 and length < text.len and text[length] & 0xc0 == 0x80) length -= 1;
        if (length < text.len) self.truncated = true;
        self.name_bytes += length;
        return self.allocator.dupe(u8, text[0..length]);
    }
    fn addNode(self: *Builder, value: Node) !u32 {
        const id: u32 = @intCast(self.nodes.items.len);
        try self.nodes.append(self.allocator, value);
        return id;
    }
    fn budget(self: *Builder, depth: usize) bool {
        if (self.remaining == 0 or depth >= 32) {
            self.truncated = true;
            return false;
        }
        self.remaining -= 1;
        return true;
    }
    fn save(self: *Builder, values: []const Edge) !Span {
        const start: u32 = @intCast(self.edges.items.len);
        try self.edges.appendSlice(self.allocator, values);
        return .{ .start = start, .len = @intCast(values.len) };
    }
    fn typeNode(self: *Builder, engine: anytype, ty: T.Id, depth: usize) T.Error!u32 {
        if (!self.budget(depth)) return 0;
        const resolved = try engine.types.resolve(ty, 0);
        if (self.memo.get(resolved)) |cached| return cached;
        const value = engine.types.node(resolved);
        const id = try self.addNode(.{ .kind = std.meta.stringToEnum(Kind, @tagName(value.tag)).? });
        try self.memo.put(self.allocator, resolved, id);
        var children: std.ArrayList(Edge) = .empty;
        defer children.deinit(self.allocator);
        errdefer for (children.items) |edge| if (edge.name) |text| self.allocator.free(text);
        switch (value.tag) {
            .variable => self.nodes.items[id].variable = value.a,
            .nominal, .type_constructor => {
                self.nodes.items[id].identity = .{ .unit = value.a, .decl = value.b };
                for (engine.nominals.items) |nominal| if (nominal.identity.unit == value.a and nominal.identity.decl == value.b) {
                    self.nodes.items[id].name = try self.saveName(engine.pool.get(nominal.name));
                    break;
                };
                if (value.tag == .nominal) {
                    const arguments = engine.types.nominalArguments(value);
                    // Recursion can relocate the store. Keep numeric list offsets.
                    const span: T.List = .{ .start = value.c + 1, .len = @intCast(arguments.len) };
                    for (0..span.len) |i| {
                        if (self.remaining == 0) {
                            self.truncated = true;
                            break;
                        }
                        const child = engine.types.list(span)[i];
                        try children.append(self.allocator, .{ .type = try self.typeNode(engine, child, depth + 1) });
                    }
                }
            },
            .function, .state_provider => {
                try children.append(self.allocator, .{ .type = try self.typeNode(engine, value.a, depth + 1) });
                try children.append(self.allocator, .{ .type = try self.typeNode(engine, value.b, depth + 1) });
                if (value.tag == .state_provider) {
                    try children.append(self.allocator, .{ .type = try self.typeNode(engine, value.c, depth + 1) });
                } else {
                    const effects = try self.row(engine, value.c, depth + 1);
                    self.nodes.items[id].effects = effects;
                }
            },
            .array, .list, .cursor, .demand, .resolver, .provider => {
                try children.append(self.allocator, .{ .type = try self.typeNode(engine, value.a, depth + 1) });
                if (value.tag == .demand or value.tag == .provider) {
                    const effects = try self.row(engine, value.c, depth + 1);
                    self.nodes.items[id].effects = effects;
                }
            },
            .product, .record => for (0..value.b) |i| {
                if (self.remaining == 0) {
                    self.truncated = true;
                    break;
                }
                const field = if (value.tag == .record) engine.types.recordField(value, i) else T.Field{ .name = 0, .ty = engine.types.list(.{ .start = value.a, .len = value.b })[i] };
                const child = try self.typeNode(engine, field.ty, depth + 1);
                const field_name = if (field.name != 0) try self.saveName(engine.pool.get(field.name)) else null;
                errdefer if (field_name) |text| self.allocator.free(text);
                try children.append(self.allocator, .{ .name = field_name, .type = child });
            },
            else => {},
        }
        self.nodes.items[id].children = try self.save(children.items);
        return id;
    }
    fn row(self: *Builder, engine: anytype, input: T.Effects.Id, depth: usize) T.Error!u32 {
        if (!self.budget(depth)) return 0;
        const id = try self.addNode(.{ .kind = .effects });
        const row_ = engine.types.effects.node(try engine.types.resolveEffects(input, 0));
        var children: std.ArrayList(Edge) = .empty;
        defer children.deinit(self.allocator);
        for (0..row_.labels.len) |i| {
            if (!self.budget(depth + 1)) break;
            const label = engine.types.effects.list(row_.labels)[i];
            const operation = engine.types.operation(label);
            const op = try self.addNode(.{ .kind = .operation, .identity = operation.identity });
            if (label == T.foreign_operation) {
                self.nodes.items[op].name = try self.saveName("Foreign");
            } else for (engine.effect_templates.items) |template| if (std.meta.eql(template.identity, operation.identity)) {
                self.nodes.items[op].name = try self.saveName(engine.pool.get(template.name));
                break;
            };
            var arguments: std.ArrayList(Edge) = .empty;
            defer arguments.deinit(self.allocator);
            for (0..operation.arguments.len) |j| {
                if (self.remaining == 0) {
                    self.truncated = true;
                    break;
                }
                const argument = engine.types.list(operation.arguments)[j];
                try arguments.append(self.allocator, .{ .type = try self.typeNode(engine, argument, depth + 1) });
            }
            self.nodes.items[op].children = try self.save(arguments.items);
            try children.append(self.allocator, .{ .type = op });
        }
        switch (row_.tail) {
            .closed => {},
            .variable, .parameter => |variable| {
                const tail = if (self.budget(depth + 1)) try self.addNode(.{ .kind = if (row_.tail == .variable) .row_variable else .row_parameter, .variable = variable }) else 0;
                try children.append(self.allocator, .{ .type = tail });
            },
        }
        self.nodes.items[id].children = try self.save(children.items);
        return id;
    }
    fn predicates(self: *Builder, engine: anytype, scheme: T.Scheme) T.Error!Span {
        const start: u32 = @intCast(self.requirements.items.len);
        for (0..scheme.obligations.len) |i| {
            if (self.requirements.items.len == 64 or self.remaining == 0) {
                self.truncated = true;
                break;
            }
            const predicate = engine.obligations.items[scheme.obligations.start + i];
            const subject = try self.typeNode(engine, predicate.ty, 0);
            const argument = if (predicate.other != 0) try self.typeNode(engine, predicate.other, 0) else null;
            const result = if (predicate.result != 0) try self.typeNode(engine, predicate.result, 0) else null;
            const signature = if (predicate.signature != 0) try self.typeNode(engine, predicate.signature, 0) else null;
            const member = if (predicate.name != 0) try self.saveName(engine.pool.get(predicate.name)) else null;
            errdefer if (member) |text| self.allocator.free(text);
            try self.requirements.append(self.allocator, .{ .kind = predicate.kind, .name = member, .subject = subject, .argument = argument, .result = result, .signature = signature, .explicit = predicate.explicit });
        }
        return .{ .start = start, .len = @as(u32, @intCast(self.requirements.items.len)) - start };
    }
};

pub fn build(engine: anytype, source: ast.Id, scope: T.List, owner: u32) T.Error!Snapshot {
    var builder: Builder = .{ .allocator = engine.allocator };
    defer builder.deinit();
    _ = try builder.addNode(.{ .kind = .truncated });
    var result: Snapshot = .{};
    errdefer result.deinit(engine.allocator);
    result.expected = try builder.typeNode(engine, engine.expr_types[source], 0);
    if (owner != 0) result.enclosing = try builder.predicates(engine, engine.bindings.items[owner].scheme);
    for (0..@min(scope.len, 32)) |i| {
        const binding = engine.bindings.items[engine.types.list(scope)[i]];
        const ty = try builder.typeNode(engine, binding.ty, 0);
        const requirements = try builder.predicates(engine, binding.scheme);
        const name = try builder.saveName(engine.pool.get(binding.name));
        errdefer builder.allocator.free(name);
        try builder.scope.append(builder.allocator, .{ .name = name, .type = ty, .requirements = requirements });
    }
    if (scope.len > 32) builder.truncated = true;
    result.nodes = try builder.nodes.toOwnedSlice(engine.allocator);
    result.edges = try builder.edges.toOwnedSlice(engine.allocator);
    result.scope = try builder.scope.toOwnedSlice(engine.allocator);
    result.requirements = try builder.requirements.toOwnedSlice(engine.allocator);
    result.truncated = builder.truncated;
    return result;
}

//! List slots can be shared, but a stored word cannot be both a symbol and a
//! type/index/count. Each symbol is rewritten once. Source record positions
//! remain unchanged; the admitted name map must be injective.
const std = @import("std");
const D = @import("frozen_dependency.zig");
const T = @import("types.zig");
const Allocator = std.mem.Allocator;
pub const Error = Allocator.Error || error{InvalidArtifact};
pub const Slots = struct {
    interface_types: []u8,
    patterns: []u8,
    core_types: []u8,
    pub fn deinit(self: *Slots, allocator: Allocator) void {
        allocator.free(self.interface_types);
        allocator.free(self.patterns);
        allocator.free(self.core_types);
    }
};
fn mark(slots: []u8, start: u32, len: u32, role: u8) Error!void {
    if (start > slots.len or len > slots.len - start) return error.InvalidArtifact;
    for (slots[start..][0..len]) |*old| {
        if (old.* != 0 and old.* != role) return error.InvalidArtifact;
        old.* = role;
    }
}
fn list(slots: []u8, value: T.List, role: u8) Error!void {
    try mark(slots, value.start, value.len, role);
}
fn scheme(slots: []u8, value: T.Scheme) Error!void {
    try list(slots, value.variables, 2);
    try list(slots, value.row_variables, 2);
    try list(slots, value.closed_rows, 2);
}
fn graph(slots: []u8, nodes: []const T.Node, extra: []const u32, operations: []const T.Operation) Error!void {
    for (nodes) |node| switch (node.tag) {
        .record => {
            const width = std.math.mul(u32, node.b, 2) catch return error.InvalidArtifact;
            if (node.a > slots.len or width > slots.len - node.a) return error.InvalidArtifact;
            for (0..node.b) |index| {
                try mark(slots, @intCast(node.a + index * 2), 1, 1);
                try mark(slots, @intCast(node.a + index * 2 + 1), 1, 2);
            }
        },
        .product => try mark(slots, node.a, node.b, 2),
        .nominal => {
            if (node.c >= extra.len) return error.InvalidArtifact;
            try mark(slots, node.c, 1, 2);
            const start = std.math.add(u32, node.c, 1) catch return error.InvalidArtifact;
            try mark(slots, start, extra[node.c], 2);
        },
        else => {},
    };
    for (operations) |operation| try list(slots, operation.arguments, 2);
}
pub fn collect(allocator: Allocator, owner: *const D.Module) Error!Slots {
    const iface = &owner.interface;
    const ir = &owner.core;
    const a = try allocator.alloc(u8, iface.graph.extra.len);
    errdefer allocator.free(a);
    const b = try allocator.alloc(u8, iface.patterns.extra.len);
    errdefer allocator.free(b);
    const c = try allocator.alloc(u8, ir.types.extra.len);
    errdefer allocator.free(c);
    @memset(a, 0);
    @memset(b, 0);
    @memset(c, 0);
    try graph(a, iface.graph.nodes, iface.graph.extra, iface.graph.operations);
    try graph(c, ir.types.nodes, ir.types.extra, ir.types.operations);
    for (iface.bindings) |value| try scheme(a, value.scheme);
    for (iface.constructors) |value| try scheme(a, value.scheme);
    for (iface.nominals) |value| {
        try list(a, value.parameters, 2);
        try list(a, value.variables, 2);
        try list(a, value.parameter_names, 1);
        try list(a, value.constructors, 2);
        try list(b, value.patterns, 2);
    }
    for (iface.effect_families) |value| {
        try list(a, value.parameters, 2);
        try list(a, value.variables, 2);
        try list(a, value.parameter_names, 1);
        try list(a, value.operations, 2);
        try list(b, value.patterns, 2);
    }
    for (iface.patterns.nodes) |node| switch (node.kind) {
        .binding => {},
        .tuple, .array => try mark(b, node.a, node.b, 2),
        .record => {
            const width = std.math.mul(u32, node.b, 2) catch return error.InvalidArtifact;
            if (node.a > b.len or width > b.len - node.a) return error.InvalidArtifact;
            for (0..node.b) |index| {
                try mark(b, @intCast(node.a + index * 2), 1, 1);
                try mark(b, @intCast(node.a + index * 2 + 1), 1, 2);
            }
        },
    };
    for (ir.bindings) |value| try scheme(c, value.scheme);
    for (ir.bodies) |value| {
        try scheme(c, value.scheme);
        try list(c, value.closed_rows, 2);
    }
    for (ir.constructors) |value| try scheme(c, value.scheme);
    for (ir.nominals) |value| {
        try list(c, value.parameters, 2);
        try list(c, value.variables, 2);
    }
    for (ir.closures) |value| try list(c, value.closed_rows, 2);
    for (ir.operation_values) |value| try list(c, value.arguments, 2);
    return .{ .interface_types = a, .patterns = b, .core_types = c };
}
pub fn rewrite(extra: []u32, slots: []const u8, symbols: []const u32) void {
    for (extra, slots) |*word, role| if (role == 1) {
        word.* = symbols[word.*];
    };
}

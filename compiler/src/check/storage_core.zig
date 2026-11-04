//! Shape evidence is separate from lifetime authority. Every operand remains
//! visible to portable Core validation; emission additionally proves its owner.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const types = @import("storage_types.zig");
const ops = @import("storage_ops.zig");
const Error = error{InvalidArtifact};
pub const Pair = struct { expected: T.Id, actual: T.Id };
pub const Contract = struct {
    pairs: [4]Pair = undefined,
    len: usize = 0,
    fn same(self: *Contract, expected: T.Id, actual: T.Id) void {
        self.pairs[self.len] = .{ .expected = expected, .actual = actual };
        self.len += 1;
    }
};
fn require(ok: bool) Error!void {
    if (!ok) return error.InvalidArtifact;
}
pub fn contract(m: *const core.Module, id: core.Id) Error!Contract {
    const n = m.node(id);
    const op = std.enums.fromInt(ops.Op, n.c) orelse return error.InvalidArtifact;
    const args = m.children(id);
    try require(args.len == ops.arity(op));
    const input = m.typeOf(args[0]);
    const kind = types.info(&m.types, input);
    const element = types.arrayElement(&m.types, input) orelse
        (if (kind) |value| (if (value.kind == .view) value.element else null) else null);
    var result: Contract = .{};
    switch (op) {
        .ref, .at, .link, .view => {
            const out = types.info(&m.types, n.ty) orelse return error.InvalidArtifact;
            try require(out.kind == @as(types.Kind, switch (op) {
                .ref, .at => .ref,
                .link => .link,
                else => .view,
            }));
            if (op == .ref) {
                const place = m.node(args[0]);
                try require(place.tag == .reference or place.tag == .project);
                result.same(input, out.element);
            } else {
                try require(element != null);
                if (op == .link) try require(kind == null or kind.?.kind == .grow);
                result.same(element.?, out.element);
                for (args[1..]) |arg| result.same(T.u32_type, m.typeOf(arg));
            }
        },
        .load, .write => {
            const target = kind orelse return error.InvalidArtifact;
            try require(target.kind == .ref or target.kind == .link);
            if (op == .load) result.same(target.element, n.ty) else {
                result.same(target.element, m.typeOf(args[1]));
                result.same(T.unit, n.ty);
            }
        },
        .length => {
            try require(element != null);
            result.same(T.u32_type, n.ty);
        },
        .read => {
            result.same(element orelse return error.InvalidArtifact, n.ty);
            result.same(T.u32_type, m.typeOf(args[1]));
        },
        .push => {
            const target = kind orelse return error.InvalidArtifact;
            try require(target.kind == .grow or target.kind == .resize);
            result.same(target.element, m.typeOf(args[1]));
            result.same(T.unit, n.ty);
        },
        .reserve => {
            const target = kind orelse return error.InvalidArtifact;
            try require(target.kind == .grow or target.kind == .resize);
            const count = m.node(args[1]);
            try require(count.tag == .constant and count.b == 0 and count.c == 0 and m.types.node(count.ty).tag == .u32);
            result.same(T.u32_type, m.typeOf(args[1]));
            result.same(T.unit, n.ty);
        },
        .pop, .truncate => {
            const target = kind orelse return error.InvalidArtifact;
            try require(target.kind == .resize);
            if (op == .pop) result.same(target.element, n.ty) else {
                result.same(T.u32_type, m.typeOf(args[1]));
                result.same(T.unit, n.ty);
            }
        },
        .freeze => {
            const target = kind orelse return error.InvalidArtifact;
            try require(target.kind == .grow or target.kind == .resize);
            const out = m.types.node(n.ty);
            try require(out.tag == .array);
            result.same(target.element, out.a);
        },
        .copy => {
            try require(element != null and (kind == null or kind.?.kind != .view));
            result.same(input, n.ty);
        },
    }
    return result;
}

pub fn validate(m: *const core.Module) Error!void {
    var present = false;
    for (m.types.nodes) |node| {
        if (node.tag != .nominal and node.tag != .projection and node.tag != .type_constructor) continue;
        if (types.identity(node.a, node.b) == null) continue;
        try require(node.tag == .nominal and m.types.nominalArguments(node).len == 1);
        present = true;
    }
    for (m.nodes) |node| if (node.tag == .storage or types.info(&m.types, node.ty) != null) {
        present = true;
        break;
    };
    if (!present) return;
    var remaining: usize = 1_000_000;
    for (m.nodes, 0..) |node, index| {
        if (node.tag == .storage) {
            const evidence = try contract(m, @intCast(index));
            for (evidence.pairs[0..evidence.len]) |pair| {
                if (pair.actual == T.never) continue;
                try require(@import("rank_equal.zig").equalWithBudget(&m.types, pair.expected, pair.actual, true, &remaining) catch return error.InvalidArtifact);
            }
        } else if (node.tag == .array) {
            const shape = m.types.node(node.ty);
            const element = if (shape.tag == .list) shape.a else types.arrayElement(&m.types, node.ty) orelse return error.InvalidArtifact;
            for (m.children(@intCast(index))) |child| {
                if (m.typeOf(child) == T.never) continue;
                try require(@import("rank_equal.zig").equalWithBudget(&m.types, element, m.typeOf(child), true, &remaining) catch return error.InvalidArtifact);
            }
        }
    }
}

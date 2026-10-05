//! Input projection for a principal constraint query. This is not an
//! executable/body identity. Only primitive literal payload bits are erased;
//! types, operators, branches, captures, positions and catalogs remain exact.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
pub fn moduleEqual(old: *const core.Module, current: *const core.Module) bool {
    inline for (@typeInfo(core.Module).@"struct".field_names) |name| {
        if (comptime !std.mem.eql(u8, name, "nodes")) {
            if (!equal(@field(old, name), @field(current, name))) return false;
        }
    }
    if (old.nodes.len != current.nodes.len) return false;
    for (old.nodes, current.nodes) |a, b| {
        var projected = b;
        if (a.tag == .constant and b.tag == .constant and a.ty == b.ty and
            (a.ty == T.unit or a.ty == T.boolean or a.ty == T.u32_type or a.ty == T.f32_type)) projected.a = a.a;
        if (!std.meta.eql(a, projected)) return false;
    }
    return true;
}
fn equal(a: anytype, b: @TypeOf(a)) bool {
    return switch (@typeInfo(@TypeOf(a))) {
        .pointer => |p| blk: {
            if (p.size != .slice) @compileError("Owned slices required");
            if (a.len != b.len) break :blk false;
            for (a, b) |x, y| if (!equal(x, y)) break :blk false;
            break :blk true;
        },
        .array => blk: {
            for (a, b) |x, y| if (!equal(x, y)) break :blk false;
            break :blk true;
        },
        .@"struct" => |info| blk: {
            inline for (info.field_names) |name| if (!equal(@field(a, name), @field(b, name))) break :blk false;
            break :blk true;
        },
        .optional => if (a) |x| if (b) |y| equal(x, y) else false else b == null,
        .@"union" => if (std.meta.activeTag(a) != std.meta.activeTag(b)) false else switch (a) {
            inline else => |x, tag| equal(x, @field(b, @tagName(tag))),
        },
        .void => true,
        else => a == b,
    };
}

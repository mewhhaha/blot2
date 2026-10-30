//! Storage capabilities are compiler-owned types, never user-defined wrappers
//! around Array. Literal context selects a mode; ordinary values never coerce.
const std = @import("std");
const T = @import("types.zig");
pub const Kind = enum(u32) { grow = 20, resize, ref, view, link };
pub const Info = struct { kind: Kind, element: T.Id };

pub fn named(spelling: []const u8) ?Kind {
    const text = if (std.mem.startsWith(u8, spelling, "@storage.")) spelling[9..] else spelling;
    inline for (.{ .{ "GrowArray", Kind.grow }, .{ "ResizeArray", Kind.resize }, .{ "Ref", Kind.ref }, .{ "View", Kind.view }, .{ "Link", Kind.link } }) |item|
        if (std.mem.eql(u8, text, item[0])) return item[1];
    return null;
}
pub fn name(kind: Kind) []const u8 {
    return switch (kind) {
        .grow => "GrowArray",
        .resize => "ResizeArray",
        .ref => "Ref",
        .view => "View",
        .link => "Link",
    };
}
pub fn identity(unit: u32, declaration: u32) ?Kind {
    if (unit != std.math.maxInt(u32)) return null;
    return std.enums.fromInt(Kind, declaration);
}
pub fn make(store: *T.Store, kind: Kind, element: T.Id) T.Error!T.Id {
    return store.nominal(.{ .unit = std.math.maxInt(u32), .decl = @backingInt(kind) }, &.{element});
}
pub fn info(store: anytype, id: T.Id) ?Info {
    const node = store.node(id);
    if (node.tag != .nominal) return null;
    const kind = identity(node.a, node.b) orelse return null;
    const arguments = store.nominalArguments(node);
    if (arguments.len != 1) return null;
    return .{ .kind = kind, .element = arguments[0] };
}
pub fn arrayElement(store: anytype, id: T.Id) ?T.Id {
    const node = store.node(id);
    if (node.tag == .array) return node.a;
    const value = info(store, id) orelse return null;
    return switch (value.kind) {
        .grow, .resize => value.element,
        else => null,
    };
}
pub fn isArray(store: anytype, id: T.Id) bool {
    return arrayElement(store, id) != null;
}

pub fn readableElement(store: anytype, id: T.Id) ?T.Id {
    if (arrayElement(store, id)) |element| return element;
    const value = info(store, id) orelse return null;
    return if (value.kind == .view) value.element else null;
}

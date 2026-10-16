//! Compile-time code shapes use compiler-owned nominal identities. Their
//! ordinary owned type arguments retain result, latent rows and qualifiers.
const std = @import("std");
const T = @import("types.zig");
pub const code_identity: T.NominalIdentity = .{ .unit = std.math.maxInt(u32), .decl = 8 };
pub const descriptor_identity: T.NominalIdentity = .{ .unit = std.math.maxInt(u32), .decl = 9 };
pub const Op = enum(u32) { quote, splice, lift, emit, run, describe, same, fields };
pub fn lookup(name: []const u8) ?Op {
    inline for (.{ .{ "@code.quote", Op.quote }, .{ "@code.splice", Op.splice }, .{ "@code.lift", Op.lift }, .{ "@code.emit", Op.emit }, .{ "@code.run", Op.run }, .{ "@code.describe", Op.describe }, .{ "@descriptor.same", Op.same }, .{ "@descriptor.fields", Op.fields } }) |item| {
        if (std.mem.eql(u8, name, item[0])) return item[1];
    }
    return null;
}
pub fn arity(op: Op) usize {
    if (op == .same) return 2;
    return 1;
}
pub fn isIdentity(unit: u32, declaration: u32) bool {
    return unit == code_identity.unit and (declaration == code_identity.decl or declaration == descriptor_identity.decl);
}
pub fn code(store: *T.Store, result: T.Id, effects: T.Effects.Id) T.Error!T.Id {
    const latent = try store.demandWithEffects(T.unit, effects);
    return store.nominal(code_identity, &.{ result, latent });
}
pub fn descriptor(store: *T.Store, target: T.Id) T.Error!T.Id {
    return store.nominal(descriptor_identity, &.{target});
}
pub const Code = struct { result: T.Id, effects: T.Effects.Id };
pub fn codeInfo(source: anytype, id: T.Id) ?Code {
    const node = source.node(id);
    if (node.tag != .nominal or node.a != code_identity.unit or node.b != code_identity.decl) return null;
    const arguments = source.nominalArguments(node);
    if (arguments.len != 2) return null;
    const latent = source.node(arguments[1]);
    if (latent.tag != .demand or latent.a != T.unit) return null;
    return .{ .result = arguments[0], .effects = latent.c };
}
pub fn descriptorInfo(source: anytype, id: T.Id) ?T.Id {
    const node = source.node(id);
    if (node.tag != .nominal or node.a != descriptor_identity.unit or node.b != descriptor_identity.decl) return null;
    const arguments = source.nominalArguments(node);
    if (arguments.len != 1) return null;
    return arguments[0];
}
pub fn liftable(source: anytype, id: T.Id) T.Error!bool {
    var remaining: usize = 4096;
    return liftableDepth(source, id, 0, &remaining);
}
pub fn compileOnly(source: anytype, raw: T.Id) T.Error!bool {
    var remaining: usize = 4096;
    return compileOnlyDepth(source, raw, 0, &remaining);
}
fn compileOnlyDepth(source: anytype, raw: T.Id, depth: usize, remaining: *usize) T.Error!bool {
    if (depth >= 128 or remaining.* == 0) return error.TypeLimit;
    remaining.* -= 1;
    const node = source.node(source.head(raw, 0));
    switch (node.tag) {
        .nominal => {
            if (isIdentity(node.a, node.b)) return true;
            for (source.nominalArguments(node)) |child| if (try compileOnlyDepth(source, child, depth + 1, remaining)) return true;
        },
        .product => for (source.list(.{ .start = node.a, .len = node.b })) |child| {
            if (try compileOnlyDepth(source, child, depth + 1, remaining)) return true;
        },
        .record => for (0..node.b) |index| {
            if (try compileOnlyDepth(source, source.recordField(node, index).ty, depth + 1, remaining)) return true;
        },
        .function => return try compileOnlyDepth(source, node.a, depth + 1, remaining) or try compileOnlyDepth(source, node.b, depth + 1, remaining),
        .usage, .array, .list, .cursor, .demand, .forall, .existential => return compileOnlyDepth(source, node.a, depth + 1, remaining),
        else => {},
    }
    return false;
}
fn liftableDepth(source: anytype, raw: T.Id, depth: usize, remaining: *usize) T.Error!bool {
    if (depth >= 128 or remaining.* == 0) return error.TypeLimit;
    remaining.* -= 1;
    const node = source.node(source.head(raw, 0));
    switch (node.tag) {
        .unit, .boolean, .u32, .f32 => return true,
        .product => {
            for (source.list(.{ .start = node.a, .len = node.b })) |child| if (!try liftableDepth(source, child, depth + 1, remaining)) return false;
        },
        .record => {
            for (0..node.b) |index| if (!try liftableDepth(source, source.recordField(node, index).ty, depth + 1, remaining)) return false;
        },
        .nominal => {
            if (isIdentity(node.a, node.b)) return false;
            for (source.nominalArguments(node)) |child| if (!try liftableDepth(source, child, depth + 1, remaining)) return false;
        },
        .array, .list => return liftableDepth(source, node.a, depth + 1, remaining),
        else => return false,
    }
    return true;
}

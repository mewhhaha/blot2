//! An opaque value has one guest word. The public storage recipe describes
//! only its machine type and ownership, with no source payload graph or names.
const T = @import("../check/types.zig");
const F = @import("../check/frozen_types.zig");
pub const Storage = struct {
    kind: enum { unknown, unit, boolean, u32, f32, reference, parameter } = .unknown,
    parameter: u32 = 0,
    /// Variable occurrence within the public parameter shape, in source order.
    selector: u32 = 0,
};
const Context = struct { parameters: []const T.Id, arguments: []const T.Id = &.{}, parent: ?*const Context = null };

pub fn infer(source: F.Source, nominals: anytype, constructors: anytype, nominal_index: u32, remaining: *usize) Storage {
    const nominal = nominals[nominal_index];
    const constructor_ids = source.list(nominal.constructors);
    if (!nominal.is_opaque or constructor_ids.len != 1) return .{};
    return inferPayload(source, nominals, constructors, constructors[constructor_ids[0]].payload, nominal.parameters, remaining);
}
pub fn inferPayload(source: F.Source, nominals: anytype, constructors: anytype, payload: T.Id, parameters: T.List, remaining: *usize) Storage {
    const context: Context = .{ .parameters = source.list(parameters) };
    return expression(source, nominals, constructors, payload, &context, 0, remaining);
}
fn expression(source: F.Source, nominals: anytype, constructors: anytype, original: T.Id, context: *const Context, depth: usize, remaining: *usize) Storage {
    if (depth >= 256 or remaining.* == 0) return .{};
    remaining.* -= 1;
    const ty = source.head(original, 0);
    const n = source.node(ty);
    switch (n.tag) {
        .unit => return .{ .kind = .unit },
        .boolean => return .{ .kind = .boolean },
        .u32, .never => return .{ .kind = .u32 },
        .f32 => return .{ .kind = .f32 },
        .variable => {
            for (context.parameters, 0..) |parameter, index| {
                if (remaining.* == 0) return .{};
                remaining.* -= 1;
                var selector: u32 = 0;
                var actual: T.Id = 0;
                if (context.parent != null) {
                    if (index >= context.arguments.len) return .{};
                    actual = context.arguments[index];
                }
                const selected = select(source, parameter, actual, .{ .ty = ty }, &selector, depth + 1, remaining) orelse continue;
                if (context.parent) |parent| {
                    return expression(source, nominals, constructors, selected.actual, parent, depth + 1, remaining);
                }
                return .{ .kind = .parameter, .parameter = @intCast(index), .selector = selected.selector };
            }
            return .{};
        },
        .nominal => {
            for (nominals) |nominal| {
                if (remaining.* == 0) return .{};
                remaining.* -= 1;
                if (nominal.identity.unit != n.a or nominal.identity.decl != n.b) continue;
                if (!nominal.is_opaque) return .{ .kind = .reference };
                const arguments = source.nominalArguments(n);
                if (nominal.storage.kind != .unknown) {
                    if (nominal.storage.kind != .parameter) return nominal.storage;
                    if (nominal.storage.parameter >= arguments.len) return .{};
                    var selected: u32 = 0;
                    const argument = selectOrdinal(source, source.list(nominal.parameters)[nominal.storage.parameter], arguments[nominal.storage.parameter], nominal.storage.selector, &selected, depth + 1, remaining) orelse return .{};
                    return expression(source, nominals, constructors, argument, context, depth + 1, remaining);
                }
                if (comptime @TypeOf(nominal.constructors) != T.List) return .{};
                const ids = source.list(.{ .start = nominal.constructors.start, .len = nominal.constructors.len });
                if (ids.len != 1) return .{};
                const nested: Context = .{ .parameters = source.list(nominal.parameters), .arguments = arguments, .parent = context };
                return expression(source, nominals, constructors, constructors[ids[0]].payload, &nested, depth + 1, remaining);
            }
            return .{};
        },
        .array, .list, .cursor, .record, .product, .function, .demand, .provider, .state_provider => return .{ .kind = .reference },
        .usage => {
            if (n.b == @backingInt(T.UsageKind.unique) or n.b == @backingInt(T.UsageKind.shared)) return .{ .kind = .reference };
            return expression(source, nominals, constructors, n.a, context, depth + 1, remaining);
        },
        .type_constructor => return .{ .kind = .u32 },
        else => return .{},
    }
}
const Selected = struct { selector: u32, actual: T.Id };
const Target = union(enum) { ty: T.Id, ordinal: u32 };
fn select(source: F.Source, parameter: T.Id, actual: T.Id, target: Target, ordinal: *u32, depth: usize, remaining: *usize) ?Selected {
    if (depth >= 256 or remaining.* == 0) return null;
    remaining.* -= 1;
    const node = source.node(source.head(parameter, 0));
    if (node.tag == .variable) {
        const selected = ordinal.*;
        ordinal.* += 1;
        const matches = switch (target) {
            .ty => |ty| source.head(parameter, 0) == ty,
            .ordinal => |index| selected == index,
        };
        if (matches) return .{ .selector = selected, .actual = actual };
        return null;
    }
    const argument = source.node(source.head(actual, 0));
    if (node.tag == .product) {
        const children = source.list(.{ .start = node.a, .len = node.b });
        for (children, 0..) |child, index| {
            var supplied: T.Id = 0;
            if (actual != 0) {
                if (argument.tag != .product or argument.b != node.b) return null;
                supplied = source.list(.{ .start = argument.a, .len = argument.b })[index];
            }
            if (select(source, child, supplied, target, ordinal, depth + 1, remaining)) |found| return found;
        }
    } else if (node.tag == .record) {
        for (0..node.b) |index| {
            const field = source.recordField(node, index);
            var supplied: T.Id = 0;
            if (actual != 0) {
                if (argument.tag != .record) return null;
                for (0..argument.b) |slot| {
                    if (remaining.* == 0) return null;
                    remaining.* -= 1;
                    const candidate = source.recordField(argument, slot);
                    if (candidate.name == field.name) {
                        supplied = candidate.ty;
                        break;
                    }
                }
                if (supplied == 0) return null;
            }
            if (select(source, field.ty, supplied, target, ordinal, depth + 1, remaining)) |found| return found;
        }
    }
    return null;
}
fn selectOrdinal(source: F.Source, parameter: T.Id, actual: T.Id, target: u32, ordinal: *u32, depth: usize, remaining: *usize) ?T.Id {
    const selected = select(source, parameter, actual, .{ .ordinal = target }, ordinal, depth, remaining) orelse return null;
    return selected.actual;
}

//! Visit the typed binding and public catalog
//! reference classes throughout owned Core/PI, including future nested fields.
//! Numeric IDs and nominal identities are not binding references.
const std = @import("std");
const core = @import("../check/core.zig");
const PI = @import("principal_interface.zig");
const D = @import("frozen_dependency.zig");
const Types = @import("../check/types.zig");
const relocation = @import("frontend_binding_relocation.zig");
const Error = error{Declined};

fn contains(comptime T: type) bool {
    @setEvalBranchQuota(20000);
    if (T == core.BindingRef or T == PI.ExternalTarget) return true;
    if (T == Types.Obligation or T == core.Obligation or T == D.Export or T == PI.Implementation) return true;
    return switch (@typeInfo(T)) {
        .pointer => |pointer| if (pointer.size == .slice) contains(pointer.child) else false,
        .optional => |optional| contains(optional.child),
        .array => |array| contains(array.child),
        .@"struct" => |info| found: {
            inline for (info.field_names) |field| if (contains(@FieldType(T, field))) break :found true;
            break :found false;
        },
        .@"union" => |info| found: {
            inline for (info.field_names) |field| if (contains(@FieldType(T, field))) break :found true;
            break :found false;
        },
        else => false,
    };
}

/// Read-only preflight. Map completeness is checked before claiming semantic
/// reuse; incomplete private targets keep ordinary checking.
pub fn admits(value: anytype, targets: relocation.Targets) bool {
    return changes(value, targets) != null;
}

/// null declines; false proves that this owner can keep its existing storage.
pub fn changes(value: anytype, targets: relocation.Targets) ?bool {
    var remaining: usize = 65_536;
    var changed = false;
    walk(false, value, targets, &remaining, &changed) catch return null;
    return changed;
}

/// Only an unpublished owned copy may be rewritten. On a decline that copy
/// must be discarded; a previous Session seed is never a destination.
pub fn rewrite(value: anytype, targets: relocation.Targets) Error!void {
    var remaining: usize = 65_536;
    var changed = false;
    return walk(true, value, targets, &remaining, &changed);
}

fn walk(comptime writing: bool, value: anytype, targets: relocation.Targets, remaining: *usize, changed: *bool) Error!void {
    const T = @typeInfo(@TypeOf(value)).pointer.child;
    if (comptime !contains(T)) return;
    if (remaining.* == 0) return error.Declined;
    remaining.* -= 1;
    if (comptime T == D.Export) {
        const mapped = targets.exported(value.*) orelse return error.Declined;
        changed.* = changed.* or !std.meta.eql(value.*, mapped);
        if (comptime writing) value.* = mapped;
        return;
    }
    if (comptime T == core.BindingRef or T == PI.ExternalTarget) {
        if (value.binding == 0) return;
        const mapped = targets.target(.{ .unit = value.unit, .binding = value.binding }) orelse return error.Declined;
        if (mapped.unit != value.unit) return error.Declined;
        changed.* = changed.* or mapped.binding != value.binding;
        if (comptime writing) value.binding = mapped.binding;
        return;
    }
    if (comptime T == PI.Implementation) {
        if (value.origin_span) |before| {
            const after = targets.qualification(value.identity.unit, before);
            changed.* = changed.* or !std.meta.eql(before, after);
            if (comptime writing) value.origin_span = after;
        }
        return;
    }
    if (comptime T == Types.Obligation or T == core.Obligation) {
        if (value.qualification_span) |before| {
            const after = targets.qualification(value.qualification_unit, before);
            changed.* = changed.* or !std.meta.eql(before, after);
            if (comptime writing) value.qualification_span = after;
        }
        // callee_use is the one predicate whose identity denotes a value
        // binding. Contract/effect/nominal identities keep their own class.
        if (value.kind == .callee_use and value.identity.decl != 0) {
            const mapped = targets.target(.{ .unit = value.identity.unit, .binding = value.identity.decl }) orelse return error.Declined;
            if (mapped.unit != value.identity.unit) return error.Declined;
            changed.* = changed.* or mapped.binding != value.identity.decl;
            if (comptime writing) value.identity.decl = mapped.binding;
        }
        return;
    }
    switch (@typeInfo(T)) {
        .pointer => |pointer| {
            if (pointer.size != .slice) @compileError("Owned reference storage must have an explicit traversal");
            for (value.*) |*item| try walk(writing, item, targets, remaining, changed);
        },
        .optional => if (value.*) |*item| try walk(writing, item, targets, remaining, changed),
        .array => for (value) |*item| try walk(writing, item, targets, remaining, changed),
        .@"struct" => |info| {
            inline for (info.field_names) |field| if (comptime contains(@FieldType(T, field))) try walk(writing, &@field(value.*, field), targets, remaining, changed);
        },
        .@"union" => |info| {
            if (info.tag_type == null) @compileError("An untagged reference union needs an explicit traversal");
            inline for (info.field_names) |field| {
                if (comptime contains(@FieldType(T, field))) {
                    if (std.meta.activeTag(value.*) == @field(std.meta.Tag(T), field)) try walk(writing, &@field(value.*, field), targets, remaining, changed);
                }
            }
        },
        else => unreachable,
    }
}

test "frontend relocation typed references preserve nominal and local IDs and preflight incomplete maps" {
    var slots = [_]u32{ 0, 0, 4 };
    const maps = [_]?relocation.Map{.{ .bindings = &slots }};
    const targets: relocation.Targets = .{ .units = &maps };
    var nested = [_]core.BindingRef{ .{ .unit = 1, .binding = 2 }, .{ .unit = 0, .binding = 2 } };
    const Example = struct { refs: []core.BindingRef, selected: ?PI.ExternalTarget, identity: Types.NominalIdentity, local: u32, callee: Types.Obligation, other: Types.Obligation };
    var value: Example = .{ .refs = &nested, .selected = .{ .unit = 1, .binding = 2 }, .identity = .{ .unit = 1, .decl = 2 }, .local = 2, .callee = .{ .ty = 0, .kind = .callee_use, .source = 0, .identity = .{ .unit = 1, .decl = 2 } }, .other = .{ .ty = 0, .kind = .type_rep, .source = 0, .identity = .{ .unit = 1, .decl = 2 } } };
    try std.testing.expect(admits(&value, targets));
    try std.testing.expectEqual(@as(u32, 2), nested[0].binding);
    try rewrite(&value, targets);
    try std.testing.expectEqual(@as(u32, 4), nested[0].binding);
    try std.testing.expectEqual(@as(u32, 2), nested[1].binding);
    try std.testing.expectEqual(@as(u32, 4), value.selected.?.binding);
    try std.testing.expectEqual(@as(u32, 2), value.identity.decl);
    try std.testing.expectEqual(@as(u32, 2), value.local);
    try std.testing.expectEqual(@as(u32, 4), value.callee.identity.decl);
    try std.testing.expectEqual(@as(u32, 2), value.other.identity.decl);
    nested[0].binding = 1;
    try std.testing.expect(!admits(&value, targets));
    try std.testing.expectEqual(@as(u32, 1), nested[0].binding);
}

test "frontend relocation forwarded public catalog positions require a complete producer map" {
    var bindings = [_]u32{ 0, 2 };
    var nominals = [_]u32{ 0, 3 };
    var constructors = [_]u32{ 0, 4 };
    const maps = [_]?relocation.Map{.{ .bindings = &bindings, .nominals = &nominals, .constructors = &constructors }};
    const targets: relocation.Targets = .{ .units = &maps };
    var exports = [_]D.Export{
        .{ .name = 7, .kind = .nominal, .target = .{ .unit = 1, .binding = 0 }, .catalog = 1 },
        .{ .name = 8, .kind = .constructor, .target = .{ .unit = 1, .binding = 0 }, .catalog = 1 },
    };
    try std.testing.expect(changes(&exports, targets).?);
    try std.testing.expectEqual(@as(u32, 1), exports[0].catalog);
    try rewrite(&exports, targets);
    try std.testing.expectEqual(@as(u32, 3), exports[0].catalog);
    try std.testing.expectEqual(@as(u32, 4), exports[1].catalog);
    try std.testing.expectEqual(@as(u32, 0), exports[0].target.binding);
    exports[0].catalog = 2;
    try std.testing.expect(!admits(&exports, targets));
    try std.testing.expectEqual(@as(u32, 2), exports[0].catalog);
}

test "frontend relocation forwarded contract catalog zero is rewritten only in an owned copy" {
    var bindings = [_]u32{0};
    var contracts = [_]u32{1};
    const maps = [_]?relocation.Map{.{ .bindings = &bindings, .contracts = &contracts }};
    const targets: relocation.Targets = .{ .units = &maps };
    var exported: D.Export = .{ .name = 7, .kind = .contract, .target = .{ .unit = 1, .binding = 0 }, .catalog = 0 };
    try std.testing.expect(changes(&exported, targets).?);
    try std.testing.expectEqual(@as(u32, 0), exported.catalog);
    try rewrite(&exported, targets);
    try std.testing.expectEqual(@as(u32, 1), exported.catalog);
    try std.testing.expectEqual(@as(u32, 0), exported.target.binding);
    exported.catalog = 2;
    try std.testing.expect(!admits(&exported, targets));
    try std.testing.expectEqual(@as(u32, 2), exported.catalog);
}

test "frontend relocation preserves contract provenance in owned principal and executable copies" {
    const ast = @import("../parse/ast.zig");
    const before: ast.Span = .{ .start = 4, .end = 9 };
    const after: ast.Span = .{ .start = 12, .end = 17 };
    var qualifications = [_]relocation.Qualification{.{ .before = before, .after = after }};
    var bindings = [_]u32{0};
    const maps = [_]?relocation.Map{.{ .bindings = &bindings, .qualifications = &qualifications }};
    const targets: relocation.Targets = .{ .units = &maps };
    const Example = struct { principal: Types.Obligation, executable: core.Obligation, unrelated: Types.Obligation };
    const original: Example = .{
        .principal = .{ .ty = 0, .kind = .type_rep, .source = 0, .explicit = true, .qualification_unit = 1, .qualification_span = before },
        .executable = .{ .ty = 0, .kind = .type_rep, .span = before, .explicit = true, .qualification_unit = 1, .qualification_span = before },
        .unrelated = .{ .ty = 0, .kind = .type_rep, .source = 0, .explicit = true, .qualification_unit = 2, .qualification_span = before },
    };
    var owned = original;
    try std.testing.expect(targets.changes());
    try std.testing.expect(changes(&owned, targets).?);
    try std.testing.expectEqualDeep(original, owned);
    try rewrite(&owned, targets);
    try std.testing.expectEqual(after, owned.principal.qualification_span.?);
    try std.testing.expectEqual(after, owned.executable.qualification_span.?);
    try std.testing.expectEqual(before, original.principal.qualification_span.?);
    try std.testing.expectEqual(before, owned.executable.span);
    try std.testing.expectEqualDeep(original.unrelated, owned.unrelated);
}

test "frontend relocation implementation origins update owned diagnostic provenance without changing declaration identities" {
    const before: @import("../parse/ast.zig").Span = .{ .start = 10, .end = 20 };
    const after: @import("../parse/ast.zig").Span = .{ .start = 40, .end = 50 };
    var qualifications = [_]relocation.Qualification{.{ .before = before, .after = after }};
    var implementations = [_]u32{1};
    const maps = [_]?relocation.Map{.{ .bindings = &.{}, .implementations = &implementations, .qualifications = &qualifications }};
    var value: PI.Implementation = .{ .origin_span = before, .identity = .{ .unit = 1, .decl = Types.opaque_name_bit | 7 }, .name = 7, .contract = .{ .unit = 2, .decl = Types.opaque_name_bit | 9 } };
    const original = value;
    const targets: relocation.Targets = .{ .units = &maps };
    try std.testing.expect(changes(&value, targets).?);
    try std.testing.expectEqual(before, value.origin_span.?);
    try rewrite(&value, targets);
    try std.testing.expectEqual(after, value.origin_span.?);
    value.origin_span = before;
    try std.testing.expectEqual(original, value);
    value.identity.unit = 2;
    try std.testing.expect(!changes(&value, targets).?);
}
